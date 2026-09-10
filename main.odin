package main

import "core:fmt"
import "core:nbio"
import "core:net"
import "core:strconv"
import "core:thread"
import "core:time"

import http "http"
import routes "routes"

REQUEST_TIMEOUT :: 10 * time.Second

/*
 ! TCP cycle (server side)
    1. Start with no socket.
    2. A socket is created.
    3. The socket is bound to a local address and port.
    4. The socket starts listening for incoming connections.
    5. A client attempts to connect.
    6. The server accepts the connection.
    7. The server and client send/ receive data.
    8. The connection is closed when finished.

    Basically, in networking the steps are:

    1. create a socket
    2. bind that socket to a certain address and port
    3. listen on it
    4. accept incoming requests
    5. recv/ send
    6. close when done

    Note: the listening socket usually remains open and keeps accepting new connections. `accept` gives the server a separete connected socket for a particular client.
  */

main :: proc() {

	context.allocator = http.init_tracking_allocator()
	defer http.report_tracked_leaks()

	if !http.init_debug() {
		return
	}

	router := http.init_router()
	defer delete(router.routes)

	http.add_route(&router, .POST, "/ping", routes.ping_handler)

	start_server(&router)
}

start_server :: proc(router: ^http.Router) {

	workers: thread.Pool
	thread.pool_init(&workers, context.allocator, 2)
	thread.pool_start(&workers)

	err := nbio.acquire_thread_event_loop()
	defer nbio.release_thread_event_loop()

	ep, _ := nbio.parse_endpoint("127.0.0.1:3000")
	socket, l_err := nbio.listen_tcp(ep)

	if l_err != nil {
		#partial switch e in l_err {
		case net.Create_Socket_Error:
			if e != .None {
				fmt.printf("Socket creation failed: %v", e)
				panic("Socket err")
			}
		case net.Bind_Error:
			if e != .None {
				fmt.printf("Bind failed: %v", e)
				panic("Bind err")
			}
		case net.Listen_Error:
			if e != .None {
				fmt.printf("Listening failed: %v", e)
				panic("Listen err")
			}
		}
	}

	fmt.printfln("Listening on 127.0.0.1:3000")
	http.debugfln("Socket fd: %v", socket)

	server_loop(socket, &workers, router)
}

server_loop :: proc(socket: nbio.TCP_Socket, workers: ^thread.Pool, router: ^http.Router) {

	work_context := http.Work_Context {
		router  = router,
		workers = workers,
	}

	nbio.accept_poly(socket, &work_context, on_accept)
	err := nbio.run()
	assert(err == nil)

	on_accept :: proc(op: ^nbio.Operation, work_context: ^http.Work_Context) {
		err := op.accept.err
		if err != .None {
			fmt.eprintfln("Accepting failed: %v", err)
			return
		}

		// Accept next connection
		nbio.accept_poly(op.accept.socket, work_context, on_accept)

		fmt.printfln(
			"Client connected: %v:%v",
			op.accept.client_endpoint.address,
			op.accept.client_endpoint.port,
		)

		// Add the work to the worker
		thread.pool_add_task(
			work_context.workers,
			context.allocator,
			do_work,
			new_clone(
				http.Task_Context {
					router = work_context.router,
					connection = http.Connection{loop = op.l, socket = op.accept.client},
				},
			),
		)
	}

	do_work :: proc(t: thread.Task) {
		task_context := (^http.Task_Context)(t.data)
		c_socket := task_context.connection.socket

		// Do the work here
		// time.sleep(time.Second * 5)
		// Set a timeout to the client socket connection to prevent server holds.
		if t_err := net.set_option(
			task_context.connection.socket,
			.Receive_Timeout,
			REQUEST_TIMEOUT,
		); t_err != .None {
			fmt.eprintfln("Could not set the receive timeout: %v", t_err)
			nbio.close(c_socket)
			free(task_context)
			return
		}

		accumulator: [8192]u8
		bytes_read, h_err := http.read_req_head(c_socket, accumulator[:])

		if h_err != nil {
			if problem, ok := h_err.(http.Read_Problem);
			   ok && problem == .Client_Disconnected && bytes_read == 0 {
				http.debugfln("Client closed before sending a request")

				nbio.close(c_socket)
				free(task_context)
				return
			}

			fmt.eprintfln("Failed to read the request head: %v", h_err)

			http.send_error(c_socket, task_context.connection.loop, read_error_status(h_err))

			free(task_context)
			return
		}

		request_bytes := accumulator[:bytes_read]

		request, body_start_idx, p_err := http.parse_http_req_head(request_bytes)

		// The parser allocates the headers map and nothing else owns it, so I have to free it
		// before this iteration ends. Without this the map leakes memory per
		// request for the lifetime of the process.
		defer delete(request.headers)

		if p_err != .None {
			fmt.eprintfln("Error occured: %v", p_err)

			if p_err == .Unsupported_Method {
				http.send_error(c_socket, task_context.connection.loop, 501, "Not Implemented")
			} else {
				http.send_error(c_socket, task_context.connection.loop, 400, "Bad Request")
			}
			free(task_context)
			return
		}

		has_body := false
		content_length_str, has_content_l := request.headers["Content-Length"]

		if has_content_l {
			c_length, ok := strconv.parse_int(content_length_str, 10)

			if !ok || c_length < 0 {
				fmt.eprintfln("Content-Length Header has invalid value: %v", content_length_str)
				http.send_error(c_socket, task_context.connection.loop, 400, "Bad Request")
				free(task_context)
				return
			}

			has_body = c_length > 0
		}

		if has_body {
			if request.method == .GET {
				// GET bodies are not supported by this server.
				http.send_error(c_socket, task_context.connection.loop, 400, "Bad Request")
				free(task_context)
				return
			}

			if err, code, reason := handle_request_with_body(
				c_socket,
				&request,
				accumulator[:],
				bytes_read,
				body_start_idx,
			); err {
				http.send_error(c_socket, task_context.connection.loop, code, reason)
				free(task_context)
				return
			}
		}

		handler, found := http.find_route(task_context.router, request.method, request.path)

		if !found {
			http.send_error(c_socket, task_context.connection.loop, 404, "Not Found")
			free(task_context)
			return
		}

		response := http.Response{}
		defer delete(response.headers)

		handler(&request, &response)

		response_buffer := http.build_response(&response)

		send_context := new(http.Send_Context)
		send_context.socket = task_context.connection.socket
		send_context.response_buffer = response_buffer

		loop := task_context.connection.loop

		free(task_context)

		nbio.send_poly(
			send_context.socket,
			{transmute([]byte)send_context.response_buffer},
			send_context,
			on_sent,
			l = loop,
		)
	}

	on_sent :: proc(op: ^nbio.Operation, send_context: ^http.Send_Context) {
		if op.send.err != nil {
			fmt.eprintfln("Error sending a response: %v", op.send.err)
		}

		http.debugfln("Response send completed: %v bytes", len(send_context.response_buffer))
		fmt.printfln("Closing the socket handle: %v", send_context.socket)

		delete(send_context.response_buffer)
		nbio.close(send_context.socket)
		free(send_context)
	}
}


read_error_status :: proc(err: http.Read_Error) -> (status_code: int, reason: string) {
	switch e in err {
	case http.Read_Problem:
		switch e {
		case .Head_Too_Large:
			return 431, "Request Header Fields Too Large"
		case .Body_Too_Large:
			return 413, "Content Too Large"
		case .Body_Truncated, .Client_Disconnected:
			return 400, "Bad Request"
		}
	case nbio.TCP_Recv_Error:
		if e == .Timeout {
			return 408, "Request Timeout"
		}
	}

	return 400, "Bad Request"
}

handle_request_with_body :: proc(
	c_socket: nbio.TCP_Socket,
	request: ^http.Request,
	accumulator: []u8,
	bytes_read: int,
	body_start_idx: int,
) -> (
	err: bool,
	code: int,
	reason: string,
) {
	content_length_str, ok := request.headers["Content-Length"]

	if !ok {
		return true, 400, "Bad Request"
	}

	c_length, is_parsed := strconv.parse_int(content_length_str, 10)
	if !is_parsed {
		fmt.eprintfln("Content-Length Header has invalid value: %v", content_length_str)
		return true, 400, "Bad Request"
	}

	if c_length <= 0 {
		return false, 0, ""
	}

	space_left := len(accumulator) - body_start_idx

	if c_length > space_left {
		fmt.eprintfln(
			"Request too large: body is %v bytes, buffer has %v left",
			c_length,
			space_left,
		)
		return true, 413, "Content Too Large"
	}

	http.debugfln("Total bytes after head read: %v", bytes_read)
	http.debugfln("Body starts at index: %v", body_start_idx)
	http.debugfln("Content-Length: %v", c_length)

	already_have := bytes_read - body_start_idx
	remaining := c_length - already_have

	http.debugfln("Body bytes already received: %v", already_have)
	http.debugfln("Body bytes remaining: %v", remaining)

	if remaining < 0 {
		fmt.eprintfln("Invalid Content-Length: %v", content_length_str)
		return true, 400, "Bad Request"
	}

	if remaining > 0 {
		extra_read, b_err := http.read_req_body(c_socket, accumulator[bytes_read:], remaining)

		if b_err != nil {
			fmt.eprintfln(
				"Failed to read the request body: %v (got %v of %v bytes)",
				b_err,
				extra_read,
				remaining,
			)
			return true, read_error_status(b_err)
		}

		http.debugfln("Additional body bytes read: %v", extra_read)
	}

	body_end := body_start_idx + c_length
	request.body = accumulator[body_start_idx:body_end]

	http.debugfln("Final body length: %v", len(request.body))
	http.debugfln("Final body: %q", string(request.body))

	return false, 0, ""
}
