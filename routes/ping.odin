package routes

import http "http"

ping_handler :: proc(req: ^http.Request, res: ^http.Response) {
	res.status_code = 200
	res.reason = "OK"
	res.body = "Pong"
}
