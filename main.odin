package main

import "core:fmt"
import "core:net"
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

    Note: the listening socket usually remains open and keeps accepting new connections.
    `accept` gives the server a separete connected socket for a particular client.
  */

main :: proc() {

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

	fmt.println("Socket fd:", socket)

	server: for {

		c_socket, source, a_err := net.accept_tcp(socket)

		if a_err != .None {
			fmt.printf("Accepting failed: %v", a_err)
			panic("Listen err")
		}

		fmt.printfln("Client address:%v\nClient port:%v", source.address, source.port)

		accumulator: [8192]u8
		http.read_req(c_socket, accumulator[:])

		net.close(c_socket)
	}
}
