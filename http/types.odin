package http

import "core:nbio"
import "core:thread"

Read_Error :: union {
	Read_Problem,
	nbio.Recv_Error,
}

Read_Problem :: enum {
	Client_Disconnected,
	Head_Too_Large,
	Body_Truncated,
	Body_Too_Large,
}

Parse_Error :: enum {
	None,
	Malformed,
	Malformed_Header,
	Request_Headers_Not_Found,
	Request_Line_Not_Found,
	Unsupported_Method,
}

HTTP_Methods :: enum {
	POST,
	GET,
	DELETE,
	PATCH,
	PUT,
	Invalid,
}

Request :: struct {
	method:  HTTP_Methods,
	path:    string,
	version: string,
	headers: map[string]string,
	body:    []u8,
}

Response :: struct {
	status_code: int,
	reason:      string,
	headers:     map[string]string,
	body:        string,
}

Connection :: struct {
	loop:   ^nbio.Event_Loop,
	socket: nbio.TCP_Socket,
}

Send_Context :: struct {
	socket:          nbio.TCP_Socket,
	response_buffer: []u8,
}

Work_Context :: struct {
	router:  ^Router,
	workers: ^thread.Pool,
}

Task_Context :: struct {
	connection: Connection,
	router:     ^Router,
}

Read_Context :: struct {
	socket:         nbio.TCP_Socket,
	accumulator:    [8192]u8,
	loop:           ^nbio.Event_Loop,
	router:         ^Router,
	used:           int,
	scan_from:      int,
	request:        Request,
	body_start_idx: int,
	content_length: int,
}
