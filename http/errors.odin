package http

import "core:nbio"
import "core:net"

read_error_status :: proc(err: Read_Error) -> (status_code: int, reason: string) {
	switch e in err {
	case Read_Problem:
		switch e {
		case .Head_Too_Large:
			return 431, "Request Header Fields Too Large"
		case .Body_Too_Large:
			return 413, "Content Too Large"
		case .Body_Truncated, .Client_Disconnected:
			return 400, "Bad Request"
		}

	case nbio.Recv_Error:
		if e == net.TCP_Recv_Error.Timeout {
			return 408, "Request Timeout"
		}
	}

	return 400, "Bad Request"
}
