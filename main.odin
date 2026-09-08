package main

import "core:fmt"
import "core:net"
import "core:strconv"
import http "http"

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
	if !http.init_debug() {
		return
	}

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

	server: for {
		c_socket, source, a_err := net.accept_tcp(socket)

		if a_err != .None {
			fmt.printf("Accepting failed: %v", a_err)
			panic("Listen err")
		}

		defer {
			fmt.printfln("Closing the socket handle: %v", c_socket)
			net.close(c_socket)
		}

		fmt.printfln("Client connected: %v:%v", source.address, source.port)

		accumulator: [8192]u8
		bytes_read := http.read_req_head(c_socket, accumulator[:])
		request_bytes := accumulator[:bytes_read]

		request, body_start_idx, err := http.parse_http_req_head(request_bytes)

		if err != .None {
			fmt.eprintfln("Error occured: %v", err)
			continue
		}

		if request.method != .POST && request.method != .PATCH && request.method != .PUT {
			continue
		}

		content_length_str, ok := request.headers["Content-Length"]
		if !ok {
			continue
		}

		c_length, is_parsed := strconv.parse_int(content_length_str, 10)
		if !is_parsed {
			fmt.eprintfln("Content-Length Header has invalid value: %v", content_length_str)
			continue
		}

		if c_length <= 0 {
			continue
		}

		if body_start_idx + c_length > len(accumulator) {
			fmt.eprintfln(
				"Request too large: need %v bytes, buffer has %v",
				body_start_idx + c_length,
				len(accumulator),
			)
			continue
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
			continue
		}

		if remaining > 0 {
			extra_read := http.read_req_body(c_socket, accumulator[bytes_read:], remaining)
			http.debugfln("Additional body bytes read: %v", extra_read)
		}

		body_end := body_start_idx + c_length
		request.body = accumulator[body_start_idx:body_end]

		http.debugfln("Final body length: %v", len(request.body))
		http.debugfln("Final body: %q", string(request.body))
	}
}
