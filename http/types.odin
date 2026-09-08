package http

Parse_Error :: enum {
	None,
	Malformed,
	Malformed_Header,
	Request_Headers_Not_Found,
	Request_Line_Not_Found,
}

Request :: struct {
	method:  string,
	path:    string,
	version: string,
	headers: map[string]string,
	body:    []u8,
}


