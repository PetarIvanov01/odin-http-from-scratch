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

add_route :: proc(router: ^Router, method: HTTP_Methods, path: string, handler: Handler) {
	router.routes[Route_Key{method = method, path = path}] = handler
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
