package http

import "core:fmt"

parse_http_req :: proc(buf: []u8) -> (Request, Parse_Error) {

	l := len(buf)

	// fmt.printfln("Original buffer: %v\n", string(buf))

	request: Request

	request_line_idx := -1

	if l < 2 {return request, .Malformed}

	// Parse the request line
	for i in 0 ..< l - 1 {
		if buf[i] == '\r' && buf[i + 1] == '\n' {
			request_line_bytes := buf[:i]
			method, path, version, err := _parse_req_line(request_line_bytes)

			if err != .None {
				return request, err
			}

			request.method = method
			request.path = path
			request.version = version

			request_line_idx = i
			break
		}
	}

	if request_line_idx == -1 {
		return request, .Request_Line_Not_Found
	}

	fmt.printfln(
		"Request line was parsed:\n  method: %v\n  path: %v\n  version: %v",
		request.method,
		request.path,
		request.version,
	)

	// Parse the headers
	request_headers_start_idx := request_line_idx + 2
	body_start_idx := -1

	for i in request_headers_start_idx ..< l - 3 {
		if buf[i] == '\r' && buf[i + 1] == '\n' && buf[i + 2] == '\r' && buf[i + 3] == '\n' {
			request_headers_bytes := buf[request_headers_start_idx:i + 2]
			headers, err := _parse_req_headers(request_headers_bytes)

			if err != .None {
				return request, err
			}

			request.headers = headers
			// This moves the index to the start of the body
			body_start_idx = i + 4
			break
		}
	}

	if body_start_idx == -1 {
		return request, .Request_Headers_Not_Found
	}

	_print_headers(request.headers)

	request.body = buf[body_start_idx:]

	return request, .None
}

_parse_req_line :: proc(buf: []u8) -> (method, path, version: string, err: Parse_Error) {
	sep_one := -1
	sep_two := -1

	for i in 0 ..< len(buf) {
		if buf[i] != ' ' {
			continue
		}

		if sep_one == -1 {
			sep_one = i
		} else {
			sep_two = i
			break
		}
	}

	if sep_one == -1 || sep_two == -1 {
		return "", "", "", .Malformed
	}

	method = string(buf[:sep_one])
	path = string(buf[sep_one + 1:sep_two])
	version = string(buf[sep_two + 1:])

	return method, path, version, .None
}

_parse_req_headers :: proc(buf: []u8) -> (map[string]string, Parse_Error) {
	headers := make(map[string]string)

	if len(buf) == 0 {
		return headers, .None
	}

	line_start := 0

	for i in 0 ..< len(buf) - 1 {
		// Find the end of the header line
		if buf[i] == '\r' && buf[i + 1] == '\n' {
			line := buf[line_start:i]

			key, value, err := _parse_header_line(line)
			if err != .None {
				return nil, err
			}

			headers[key] = value
			line_start = i + 2
		}
	}

	return headers, .None
}

_parse_header_line :: proc(line: []u8) -> (key, value: string, err: Parse_Error) {
	separator := -1

	for j in 0 ..< len(line) {
		if line[j] == ':' {
			separator = j
			break
		}
	}

	if separator == -1 {
		return "", "", .Malformed_Header
	}

	key = string(line[:separator])

	value_start := separator + 1

	// skip the space after the separator
	if value_start < len(line) && line[value_start] == ' ' {
		value_start += 1
	}

	value = string(line[value_start:])

	return key, value, .None
}

_print_headers :: proc(headers: map[string]string) {
	fmt.printfln("Request headers were parsed:")

	for key, value in headers {
		fmt.printfln("%v: %v", key, value)
	}
}
