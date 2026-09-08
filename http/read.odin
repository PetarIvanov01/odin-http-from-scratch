package http

import "core:fmt"
import "core:net"

read_req_head :: proc(socket: net.TCP_Socket, accumulator: []u8) -> (bytes_used: int) {
	used := 0

	read: for {
		chunk: [512]u8
		c_sl := chunk[:]

		bytes_read, r_err := net.recv_tcp(socket, c_sl)

		if r_err != .None {
			fmt.printf("Recv failed: %v", r_err)
			panic("Recv err")
		}

		if used + bytes_read > len(accumulator) {
			panic("Request too large")
		}

		copy(accumulator[used:used + bytes_read], chunk[:bytes_read])

		used += bytes_read

		if used >= 4 {
			for i in 0 ..< used - 3 {
				if accumulator[i] == '\r' &&
				   accumulator[i + 1] == '\n' &&
				   accumulator[i + 2] == '\r' &&
				   accumulator[i + 3] == '\n' {
					break read
				}
			}
		}
	}

	return used
}

read_req_body :: proc(
	socket: net.TCP_Socket,
	accumulator: []u8,
	bytes_needed: int,
) -> (
	bytes_used: int,
) {
	used := 0

	for used < bytes_needed {

		remaining := bytes_needed - used

		bytes_read, r_err := net.recv_tcp(socket, accumulator[used:used + remaining])

		if r_err != .None {
			fmt.printf("Recv failed: %v", r_err)
			panic("Recv err")
		}

		// Handles cases where the client disconnects before the full body is received.
		if bytes_read == 0 {
			break
		}

		used += bytes_read
	}

	return used
}
