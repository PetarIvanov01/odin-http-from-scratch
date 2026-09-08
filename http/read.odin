package http

import "core:net"

read_req_head :: proc(
	socket: net.TCP_Socket,
	accumulator: []u8,
) -> (
	bytes_used: int,
	err: Read_Error,
) {
	used := 0
	scan_from := 0

	for {
		if used == len(accumulator) {
			return used, Read_Problem.Head_Too_Large
		}

		bytes_read, r_err := net.recv_tcp(socket, accumulator[used:])

		if r_err != .None {
			return used, r_err
		}

		// `core:net` documents an orderly shutdown as "0 bytes read, no error".
		if bytes_read == 0 {
			return used, Read_Problem.Client_Disconnected
		}

		used += bytes_read

		for i in scan_from ..< used - 3 {
			if accumulator[i] == '\r' &&
			   accumulator[i + 1] == '\n' &&
			   accumulator[i + 2] == '\r' &&
			   accumulator[i + 3] == '\n' {
				return used, nil
			}
		}

		scan_from = max(used - 3, 0)
	}
}

read_req_body :: proc(
	socket: net.TCP_Socket,
	accumulator: []u8,
	bytes_needed: int,
) -> (
	bytes_used: int,
	err: Read_Error,
) {
	if bytes_needed > len(accumulator) {
		return 0, Read_Problem.Body_Too_Large
	}

	used := 0

	for used < bytes_needed {
		bytes_read, r_err := net.recv_tcp(socket, accumulator[used:bytes_needed])

		if r_err != .None {
			return used, r_err
		}

		if bytes_read == 0 {
			return used, Read_Problem.Body_Truncated
		}

		used += bytes_read
	}

	return used, nil
}
