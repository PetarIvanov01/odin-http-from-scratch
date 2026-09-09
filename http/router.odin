package http

Handler :: #type proc(req: ^Request, res: ^Response)

Route :: struct {
	method:  HTTP_Methods,
	path:    string,
	handler: Handler,
}

Router :: struct {
	routes: [dynamic]Route,
}

// Returns the Router by value.
// The dynamic route storage is allocator-backed, so the caller
// is responsible for deleting router.routes when done.
init_router :: proc() -> Router {
	router: Router
	router.routes = make([dynamic]Route)

	return router
}

add_route :: proc(router: ^Router, method: HTTP_Methods, path: string, handler: Handler) {
	append(&router.routes, Route{method = method, path = path, handler = handler})
}
