package http

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
