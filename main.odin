package main

import "core:fmt"
import "core:nbio"
import "core:net"
import "core:thread"

import http "http"
import routes "routes"

main :: proc() {

	context.allocator = http.init_tracking_allocator()
	defer http.report_tracked_leaks()

	if !http.init_debug() {
		return
	}

	router := http.init_router()
	defer delete(router.routes)

	http.get(&router, "/pong", routes.pong_handler)
	http.post(&router, "/ping", routes.ping_handler)

	start_server(&router)
}

THREAD_COUNT :: 8

start_server :: proc(router: ^http.Router) {

	workers: thread.Pool
	thread.pool_init(&workers, context.allocator, THREAD_COUNT)
	thread.pool_start(&workers)

	err := nbio.acquire_thread_event_loop()
	defer nbio.release_thread_event_loop()

	ep, _ := nbio.parse_endpoint("127.0.0.1:3000")
	socket, l_err := nbio.listen_tcp(ep)

	if l_err != nil {
		#partial switch e in l_err {
		case net.Create_Socket_Error:
			if e != .None {
				fmt.printf("Socket creation failed: %v", e)
				panic("Socket err")
			}
		case net.Bind_Error:
			if e != .None {
				fmt.printf("Bind failed: %v", e)
				panic("Bind err")
			}
		case net.Listen_Error:
			if e != .None {
				fmt.printf("Listening failed: %v", e)
				panic("Listen err")
			}
		}
	}

	fmt.printfln("Listening on 127.0.0.1:3000")
	http.debugfln("Socket fd: %v", socket)

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
		err := op.accept.err
		if err != .None {
			fmt.eprintfln("Accepting failed: %v", err)
			return
		}

		// Accept next connection
		nbio.accept_poly(op.accept.socket, work_context, on_accept)

		fmt.printfln(
			"Client connected: %v:%v",
			op.accept.client_endpoint.address,
			op.accept.client_endpoint.port,
		)

		// Add the work to the worker
		thread.pool_add_task(
			work_context.workers,
			context.allocator,
			do_work,
			new_clone(
				http.Task_Context {
					router = work_context.router,
					connection = http.Connection{loop = op.l, socket = op.accept.client},
				},
			),
		)
	}

	do_work :: proc(t: thread.Task) {
		task_context := (^http.Task_Context)(t.data)

		read_context := new(http.Read_Context)
		read_context.loop = task_context.connection.loop
		read_context.socket = task_context.connection.socket
		read_context.router = task_context.router

		free(task_context)

		http.read_req_head(read_context)
	}

	on_sent :: proc(op: ^nbio.Operation, send_context: ^http.Send_Context) {
		if op.send.err != nil {
			fmt.eprintfln("Error sending a response: %v", op.send.err)
		}

		http.debugfln("Response send completed: %v bytes", len(send_context.response_buffer))
		fmt.printfln("Closing the socket handle: %v", send_context.socket)

		delete(send_context.response_buffer)
		nbio.close(send_context.socket)
		free(send_context)
	}
}
