# odin-server

A minimal HTTP/1.1 server written from scratch in [Odin](https://odin-lang.org/), on raw TCP sockets. Learning project — no framework, nothing outside Odin's core library.

## What it does

- Non-blocking I/O on a `core:nbio` event loop — accepts and reads are async, many connections in flight at once
- Parses the request line, headers, and a `Content-Length` body (8 KB total per request)
- Routes on method + path via `map[Route_Key]Handler`
- Handlers fill a `Response`; `build_response` serialises it and always answers — `400`, `404`, `408`, `413`, `431`, `501` on the failure paths
- 10 s receive timeout per read, so a stalled client can't hang the process
- Uses Odin's built-in `core:log` console logger

Methods: `GET`, `POST`, `PUT`, `PATCH`, `DELETE`.

Reading a request is a state machine over nbio callbacks. Socket reads and
writes stay on the event loop, while complete request heads and bodies are
submitted to the worker pool for parsing, routing, and handler execution. The
per-connection state lives in a `Read_Context`, and a body arriving across
several `recv` callbacks is reassembled as it comes.

## Biggest bottleneck

The event loop owns socket I/O, while request parsing and handler execution run
on the worker pool. A slow handler therefore does not block socket reads for
every other connection, but the event loop still serializes accept, receive,
and send callbacks.

## Layout

```
main.odin           event loop setup, accept loop, worker pool
routes/ping.odin    example handler
http/types.odin     Request, Response, Read_Context, method and error types
http/read.odin      async reads plus worker dispatch for request processing
http/parse.odin     request line and header parsing
http/router.odin    route table, add_route / find_route
http/response.odin  response serialisation, send_error
http/errors.odin    read error -> status code mapping
core:log            built-in logging, controlled by `ENABLE_DEBUG`
```

## Run

```sh
odin run .
```

Debug logging is disabled by default. Enable it at compile time when inspecting
requests and headers:

```sh
odin run . -define:ENABLE_DEBUG=true
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
