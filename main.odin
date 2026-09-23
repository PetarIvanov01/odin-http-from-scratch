package main

import "core:log"
import "core:nbio"
import "core:net"
import "core:thread"

import http "http"
import routes "routes"

main :: proc() {
	logger_level := log.Level.Info
	when ODIN_DEBUG {
		logger_level = log.Level.Debug
	}

	context.logger = log.create_console_logger(logger_level)
	defer log.destroy_console_logger(context.logger)

	router := http.init_router()
	defer delete(router.routes)

	http.get(&router, "/pong", routes.pong_handler)
	http.post(&router, "/ping", routes.ping_handler)

	start_server(&router)
}

THREAD_COUNT :: 8
SERVER_ADDRESS :: "127.0.0.1:8080"

start_server :: proc(router: ^http.Router) {

	workers: thread.Pool
	thread.pool_init(&workers, context.allocator, THREAD_COUNT)
	thread.pool_start(&workers)

	err := nbio.acquire_thread_event_loop()
	defer nbio.release_thread_event_loop()

	ep, _ := nbio.parse_endpoint(SERVER_ADDRESS)
	socket, l_err := nbio.listen_tcp(ep)

	if l_err != nil {
		#partial switch e in l_err {
		case net.Create_Socket_Error:
			if e != .None {
				log.panicf("Socket creation failed: %v", e)
			}
		case net.Bind_Error:
			if e != .None {
				log.panicf("Bind failed: %v", e)
			}
		case net.Listen_Error:
			if e != .None {
				log.panicf("Listening failed: %v", e)
			}
		}
	}

	log.debugf("Socket fd: %v", socket)
	log.infof("Listening on %s", SERVER_ADDRESS)

	server_loop(socket, &workers, router)
}

server_loop :: proc(socket: nbio.TCP_Socket, workers: ^thread.Pool, router: ^http.Router) {

	work_context := http.Work_Context {
		router  = router,
		workers = workers,
	}

	nbio.accept_poly(socket, &work_context, on_accept)
	err := nbio.run()
	assert(err == nil)

	on_accept :: proc(op: ^nbio.Operation, work_context: ^http.Work_Context) {
		// Accept next connection
		nbio.accept_poly(op.accept.socket, work_context, on_accept)

		err := op.accept.err
		if err != .None {
			log.debugf("Accepting failed: %v", err)
			return
		}

		drain_completed_worker_tasks(work_context.workers)

		log.debugf(
			"Client connected: %v:%v",
			op.accept.client_endpoint.address,
			op.accept.client_endpoint.port,
		)

		read_context := new(http.Read_Context)
		read_context.loop = op.l
		read_context.socket = op.accept.client
		read_context.router = work_context.router
		read_context.workers = work_context.workers

		http.recv_request_head(read_context)
	}

	on_sent :: proc(op: ^nbio.Operation, send_context: ^http.Send_Context) {
		if op.send.err != nil {
			log.debugf("Error sending a response: %v", op.send.err)
		}

		log.debugf("Response send completed: %v bytes", len(send_context.response_buffer))
		log.debugf("Closing the socket handle: %v", send_context.socket)

		delete(send_context.response_buffer)
		nbio.close(send_context.socket)
		free(send_context)
	}
}

drain_completed_worker_tasks :: proc(workers: ^thread.Pool) {
	for {
		_, ok := thread.pool_pop_done(workers)
		if !ok {
			break
		}
	}
}
