package http

Handler :: #type proc(req: ^Request, res: ^Response)

Route_Key :: struct {
	method: HTTP_Methods,
	path:   string,
}

Router :: struct {
	routes: map[Route_Key]Handler,
}

// Returns the Router by value.
// The dynamic route storage is allocator-backed, so the caller
// is responsible for deleting router.routes when done.
init_router :: proc() -> Router {
	router: Router
	router.routes = make(map[Route_Key]Handler)

	return router
}

get :: proc(router: ^Router, path: string, handler: Handler) {
	_add_route(router, .GET, path, handler)
}

post :: proc(router: ^Router, path: string, handler: Handler) {
	_add_route(router, .POST, path, handler)
}

find_route :: proc(
	router: ^Router,
	method: HTTP_Methods,
	path: string,
) -> (
	handler: Handler,
	found: bool,
) {
	handler = router.routes[Route_Key{method = method, path = path}] or_return
	found = true
	return
}

_add_route :: proc(router: ^Router, method: HTTP_Methods, path: string, handler: Handler) {
	router.routes[Route_Key{method = method, path = path}] = handler
}
