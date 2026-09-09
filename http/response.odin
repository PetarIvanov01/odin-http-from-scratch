package http

import "core:fmt"

build_response :: proc(response: ^Response) -> (buffer: []u8, bytes_used: int) {
	buffer = make([]u8, 8192)
	bytes_used = 0

	status_line := fmt.bprintf(
		buffer[bytes_used:],
		"HTTP/1.1 %v %s\r\n",
		response.status_code,
		response.reason,
	)

	bytes_used += len(status_line)

	content_length := fmt.bprintf(
		buffer[bytes_used:],
		"Content-Length: %v\r\n",
		len(response.body),
	)

	bytes_used += len(content_length)

	headers := fmt.bprintf(buffer[bytes_used:], "Content-Type: text/plain\r\n\r\n")

	bytes_used += len(headers)

	body := fmt.bprintf(buffer[bytes_used:], "%s", response.body)

	bytes_used += len(body)

	return buffer, bytes_used
}
