package main

import "core:fmt"
import "core:net"
import "core:strconv"
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
	address: net.IP4_Address = {127, 0, 0, 1}
	port: int = 3000
	endpoint := net.Endpoint{address, port}

	socket, l_err := net.listen_tcp(endpoint)

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

	server_loop(socket, router)
}

server_loop :: proc(socket: net.TCP_Socket, router: ^http.Router) {

	for {
		c_socket, source, a_err := net.accept_tcp(socket)

		if a_err != .None {
			fmt.eprintfln("Accepting failed: %v", a_err)
			continue
		}

		defer {
			fmt.printfln("Closing the socket handle: %v", c_socket)
			net.close(c_socket)
		}

		fmt.printfln("Client connected: %v:%v", source.address, source.port)

		// Set a timeout to the client socket connection to prevent server holds.
		if t_err := net.set_option(c_socket, .Receive_Timeout, REQUEST_TIMEOUT); t_err != .None {
			fmt.eprintfln("Could not set the receive timeout: %v", t_err)
			continue
		}

		accumulator: [8192]u8
		bytes_read, h_err := http.read_req_head(c_socket, accumulator[:])

		if h_err != nil {
			if problem, ok := h_err.(http.Read_Problem);
			   ok && problem == .Client_Disconnected && bytes_read == 0 {
				http.debugfln("Client closed before sending a request")
			} else {
				fmt.eprintfln("Failed to read the request head: %v", h_err)
			}
			continue
		}

		request_bytes := accumulator[:bytes_read]

		request, body_start_idx, p_err := http.parse_http_req_head(request_bytes)

		// The parser allocates the headers map and nothing else owns it, so I have to free it
		// before this iteration ends. Without this the map leakes memory per
		// request for the lifetime of the process.
		defer delete(request.headers)

		if p_err != .None {
			fmt.eprintfln("Error occured: %v", p_err)
			continue
		}

		has_body := false
		content_length_str, has_content_l := request.headers["Content-Length"]

		if has_content_l {
			c_length, ok := strconv.parse_int(content_length_str, 10)

			if !ok || c_length < 0 {
				fmt.eprintfln("Content-Length Header has invalid value: %v", content_length_str)
				continue
			}

			has_body = c_length > 0
		}

		if request.method != .GET &&
		   request.method != .POST &&
		   request.method != .PATCH &&
		   request.method != .PUT &&
		   request.method != .DELETE {
			continue
		}

		if has_body {
			if request.method == .GET {
				// GET bodies are not supported by this server.
				continue
			}

			if !handle_request_with_body(
				c_socket,
				&request,
				accumulator[:],
				bytes_read,
				body_start_idx,
			) {
				continue
			}
		}

		// TODO:  Find the rotue needed to be called
		handler, found := http.find_handler(router, request.method, request.path)

		if !found {
			// 404 response
			continue
		}

		response := http.Response{}
		handler(&request, &response)

		buff, bytes_used := http.build_response(&response)
		defer delete(buff)

		bytes_written, err := net.send_tcp(c_socket, buff[:bytes_used])

		if err != nil {
			fmt.eprintfln("Error sending a response: %v", err)
			continue
		}

		http.debugfln("Response bytes written: %v%v", bytes_written, bytes_used)
	}
}

handle_request_with_body :: proc(
	c_socket: net.TCP_Socket,
	request: ^http.Request,
	accumulator: []u8,
	bytes_read: int,
	body_start_idx: int,
) -> bool {
	content_length_str, ok := request.headers["Content-Length"]

	if !ok {
		return false
	}

	c_length, is_parsed := strconv.parse_int(content_length_str, 10)
	if !is_parsed {
		fmt.eprintfln("Content-Length Header has invalid value: %v", content_length_str)
		return false
	}

	if c_length <= 0 {
		return true
	}

	space_left := len(accumulator) - body_start_idx

	if c_length > space_left {
		fmt.eprintfln(
			"Request too large: body is %v bytes, buffer has %v left",
			c_length,
			space_left,
		)
		return false
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
		return false
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
			return false
		}

		http.debugfln("Additional body bytes read: %v", extra_read)
	}

	body_end := body_start_idx + c_length
	request.body = accumulator[body_start_idx:body_end]

	http.debugfln("Final body length: %v", len(request.body))
	http.debugfln("Final body: %q", string(request.body))

	return true
}
