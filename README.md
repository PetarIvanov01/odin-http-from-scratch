# odin-server

A minimal HTTP/1.1 server written from scratch in [Odin](https://odin-lang.org/), on raw TCP sockets. Learning project — no framework, nothing outside Odin's core library.

## What it does

- Non-blocking I/O on a `core:nbio` event loop — accepts and reads are async, many connections in flight at once
- Parses the request line, headers, and a `Content-Length` body (8 KB total per request)
- Routes on method + path via `map[Route_Key]Handler`
- Handlers fill a `Response`; `build_response` serialises it and always answers — `400`, `404`, `408`, `413`, `431`, `501` on the failure paths
- 10 s receive timeout per read, so a stalled client can't hang the process
- Wraps `context.allocator` in a tracking allocator for leak reporting

Methods: `GET`, `POST`, `PUT`, `PATCH`, `DELETE`.

Reading a request is a state machine over nbio callbacks — `read_req_head` →
`handle_complete_head` → `read_req_body` → `handle_complete_body` →
`handle_complete_request` — with the per-connection state in a `Read_Context`.
A body arriving across several `recv` callbacks is reassembled as it comes.

## Biggest bottleneck

**Handlers run on the event loop thread.** The I/O path is properly async — 8
simultaneous connections finish together in about half a second. But
`handle_complete_request`, and with it the handler, `parse_http_req_head` and
`build_response`, runs inside an nbio callback on the loop thread. The worker
pool only builds a `Read_Context` and issues the first read, then returns.

So anything slow in a handler serializes every other connection: six concurrent
requests with a 3 s handler take 18 s, not 3.

Fixing it means dispatching the handler onto the worker pool and submitting the
send back to the loop with `l = ctx.loop`, which is the model `core:nbio`
documents for worker threads.

## Layout

```
main.odin           event loop setup, accept loop, worker pool
routes/ping.odin    example handler
http/types.odin     Request, Response, Read_Context, method and error types
http/read.odin      async read state machine, from first recv to response
http/parse.odin     request line and header parsing
http/router.odin    route table, add_route / find_route
http/response.odin  response serialisation, send_error
http/errors.odin    read error -> status code mapping
http/debug.odin     --debug flag, logging, allocation tracking
```

## Run

```sh
odin run .              # add -- -debug for verbose logging
```

## Try it

```sh
curl -X POST http://127.0.0.1:3000/ping     # 200 Pong
curl http://127.0.0.1:3000/ping             # 404, wrong method
```

Register more routes in `main`:

```odin
http.add_route(&router, .GET, "/health", routes.health_handler)
```
