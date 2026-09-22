package http

import "core:fmt"
import "core:nbio"
import "core:strconv"
import "core:thread"
import "core:time"

REQUEST_TIMEOUT :: 10 * time.Second

// Begin async receiving an HTTP request head
recv_request_head :: proc(ctx: ^Read_Context) {
	if ctx.used == len(ctx.accumulator) {
		send_error(ctx.socket, ctx.loop, 431, "Request Header Fields Too Large")

		free(ctx)
		return
	}

	// Schedule an async receive on the connections event loop.
	nbio.recv_poly(
		ctx.socket,
		{ctx.accumulator[ctx.used:]},
		ctx,
		on_recv,
		timeout = REQUEST_TIMEOUT,
		l = ctx.loop,
	)

	on_recv :: proc(op: ^nbio.Operation, ctx: ^Read_Context) {
		bytes_read := op.recv.received
		r_err := op.recv.err

		if r_err != nil {
			fmt.eprintfln("Failed to read the request head: %v", r_err)
			send_error(ctx.socket, ctx.loop, read_error_status(r_err))
			free(ctx)
			return
		}

		if bytes_read == 0 {
			debugfln("Client closed before sending a request")

			nbio.close(ctx.socket)
			free(ctx)
			return
		}

		ctx.used += bytes_read

		// Scan only the new area, while preserving the last
		// 3 bytes of the previous read in case "\r\n\r\n"
		// crosses recv boundaries.
		if ctx.used >= 4 {
			for i in ctx.scan_from ..< ctx.used - 3 {
				if ctx.accumulator[i] == '\r' &&
				   ctx.accumulator[i + 1] == '\n' &&
				   ctx.accumulator[i + 2] == '\r' &&
				   ctx.accumulator[i + 3] == '\n' {

					/*
					 The complete header has been received.
					 Move HTTP parsing and request proecsing off the event-loop
					 thread and onto a worker thread.
					*/
					thread.pool_add_task(ctx.workers, context.allocator, request_head_task, ctx)
					return
				}
			}
		}

		if ctx.used == len(ctx.accumulator) {
			send_error(ctx.socket, ctx.loop, 431, "Request Header Fields Too Large")

			free(ctx)
			return
		}

		ctx.scan_from = max(ctx.used - 3, 0)

		nbio.recv_poly(
			ctx.socket,
			{ctx.accumulator[ctx.used:]},
			ctx,
			on_recv,
			timeout = REQUEST_TIMEOUT,
			l = ctx.loop,
		)
	}
}

// Worker pool entry point for processing a complete request head.
request_head_task :: proc(t: thread.Task) {
	ctx := (^Read_Context)(t.data)
	process_request_head(ctx)
}

recv_request_body :: proc(ctx: ^Read_Context) {
	body_end := ctx.body_start_idx + ctx.content_length

	if body_end > len(ctx.accumulator) {
		send_error(ctx.socket, ctx.loop, 413, "Content Too Large")

		delete(ctx.request.headers)
		free(ctx)
		return
	}

	if ctx.used >= body_end {
		// The body was already received along with the request head.
		// We are already on a worker thread, so conttinue processing here.
		process_request_body(ctx)
		return
	}

	// The full body was not received with the request head.
	// This schedules the remaining body receive on the connection event loop
	nbio.recv_poly(
		ctx.socket,
		{ctx.accumulator[ctx.used:body_end]},
		ctx,
		on_body_recv,
		timeout = REQUEST_TIMEOUT,
		l = ctx.loop,
	)

	on_body_recv :: proc(op: ^nbio.Operation, ctx: ^Read_Context) {
		if op.recv.err != nil {
			fmt.eprintfln("Failed to read request body: %v", op.recv.err)

			send_error(ctx.socket, ctx.loop, read_error_status(op.recv.err))

			delete(ctx.request.headers)
			free(ctx)
			return
		}

		if op.recv.received == 0 {
			send_error(ctx.socket, ctx.loop, 400, "Bad Request")

			delete(ctx.request.headers)
			free(ctx)
			return
		}

		ctx.used += op.recv.received

		body_end := ctx.body_start_idx + ctx.content_length

		/*
		The body is complete. Move processing back to the worker pool so parsing/routing and handler
		work does not run on the event-loop thread.
		*/
		if ctx.used >= body_end {
			thread.pool_add_task(ctx.workers, context.allocator, request_body_task, ctx)
			return
		}

		nbio.recv_poly(
			ctx.socket,
			{ctx.accumulator[ctx.used:body_end]},
			ctx,
			on_body_recv,
			timeout = REQUEST_TIMEOUT,
			l = ctx.loop,
		)
	}
}

// Worker pool entry point after the complete request body has arrived.
request_body_task :: proc(t: thread.Task) {
	ctx := (^Read_Context)(t.data)
	process_request_body(ctx)
}

// (worker) processing after a complete HTTP request head is available.
process_request_head :: proc(ctx: ^Read_Context) {
	request_bytes := ctx.accumulator[:ctx.used]

	request, body_start_idx, p_err := parse_http_req_head(request_bytes)

	ctx.request = request
	ctx.body_start_idx = body_start_idx

	if p_err != .None {
		if p_err == .Unsupported_Method {
			send_error(ctx.socket, ctx.loop, 501, "Not Implemented")
		} else {
			send_error(ctx.socket, ctx.loop, 400, "Bad Request")
		}

		delete(request.headers)
		free(ctx)
		return
	}

	has_body := false
	content_length_str, has_content_l := request.headers["Content-Length"]

	if has_content_l {
		c_length, ok := strconv.parse_int(content_length_str, 10)

		if !ok || c_length < 0 {
			fmt.eprintfln("Content-Length Header has invalid value: %v", content_length_str)

			delete(request.headers)
			send_error(ctx.socket, ctx.loop, 400, "Bad Request")
			free(ctx)
			return
		}

		has_body = c_length > 0
		ctx.content_length = c_length
	}

	if has_body {
		if request.method == .GET {
			// GET bodies are not supported by this server.
			delete(request.headers)
			send_error(ctx.socket, ctx.loop, 400, "Bad Request")
			free(ctx)
			return
		}

		recv_request_body(ctx)
		return
	}

	debugfln(
		"Parsed request: method=%v path=%v body_start=%v",
		request.method,
		request.path,
		body_start_idx,
	)

	dispatch_request(ctx)
	return
}

// (worker) processing after a complete request body is available.
process_request_body :: proc(ctx: ^Read_Context) {
	body_end := ctx.body_start_idx + ctx.content_length

	ctx.request.body = ctx.accumulator[ctx.body_start_idx:body_end]

	debugfln("Final body length: %v", len(ctx.request.body))
	debugfln("Final body: %q", string(ctx.request.body))

	dispatch_request(ctx)
}

// Route the complete request, call handler, build response, and submit
// the response send to the connections event loop.
dispatch_request :: proc(ctx: ^Read_Context) {
	handler, found := find_route(ctx.router, ctx.request.method, ctx.request.path)

	if !found {
		send_error(ctx.socket, ctx.loop, 404, "Not Found")
		delete(ctx.request.headers)
		free(ctx)
		return
	}

	response := Response{}

	handler(&ctx.request, &response)

	response_buffer := build_response(&response)

	send_context := new(Send_Context)
	send_context.socket = ctx.socket
	send_context.response_buffer = response_buffer
	loop := ctx.loop

	delete(ctx.request.headers)
	free(ctx)

	nbio.send_poly(
		send_context.socket,
		{send_context.response_buffer},
		send_context,
		on_sent,
		l = loop,
	)
}
