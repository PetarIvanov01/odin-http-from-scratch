package http

import "core:fmt"
import "core:nbio"
import "core:strings"

build_response :: proc(response: ^Response) -> []u8 {
	builder := strings.builder_make()

	fmt.sbprintf(&builder, "HTTP/1.1 %v %s\r\n", response.status_code, response.reason)
	fmt.sbprintf(&builder, "Content-Length: %v\r\n", len(response.body))
	fmt.sbprintf(&builder, "Connection: close\r\n")

	has_content_type := false

	for key, value in response.headers {
		if strings.equal_fold(key, "Content-Length") || strings.equal_fold(key, "Connection") {
			continue
		}

		if strings.equal_fold(key, "Content-Type") {
			has_content_type = true
		}

		fmt.sbprintf(&builder, "%s: %s\r\n", key, value)
	}

	if !has_content_type {
		fmt.sbprintf(&builder, "Content-Type: text/plain\r\n")
	}

	fmt.sbprintf(&builder, "\r\n%s", response.body)

	return builder.buf[:]
}

send_error :: proc(
	socket: nbio.TCP_Socket,
	loop: ^nbio.Event_Loop,
	status_code: int,
	reason: string,
) {
	response := Response {
		status_code = status_code,
		reason      = reason,
		body        = reason,
	}

	response_buffer := build_response(&response)

	send_context := new(Send_Context)
	send_context.socket = socket
	send_context.response_buffer = response_buffer

	nbio.send_poly(socket, {transmute([]byte)response_buffer}, send_context, on_sent, l = loop)
}

on_sent :: proc(op: ^nbio.Operation, send_context: ^Send_Context) {
	if op.send.err != nil {
		debugfln("Could not send response: %v", op.send.err)
	}

	delete(send_context.response_buffer)
	nbio.close(send_context.socket)
	free(send_context)
}
