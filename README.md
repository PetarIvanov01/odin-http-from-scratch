# Pet Project

A small HTTP/1.1 server written from scratch in [Odin](https://odin-lang.org/).
I made it to learn how an HTTP server works under the framework level, from
accepting a TCP connection to parsing a request and sending the response back.

## What it does

- uses non-blocking I/O from `core:nbio`, so many connections can be in progress without blocking the main thread
- parses the request line, headers, and a body described by `Content-Length`
- routes requests by HTTP method + path
- executes parsing, routing, handlers, and response building on a worker pool
- lets handlers set the status, headers, and body of the response
- handles failure paths with `400`, `404`, `408`, `413`, `431`, and `501`
- gives each receive operation a 10 second timeout, so a stalled client can't hang the process

Reading a request is like a state machine over nbio callbacks.
I separate the work between the I/O thread (the main one) and worker threads.
Accepting connections, receiving bytes, and sending bytes stay on the I/O
thread. Work like parsing the request, building the headers map, finding the
route, running the handler, and building the response is executed on worker
threads.

## Current HTTP limits

- the server listens on `127.0.0.1:8080`
- the parser recognizes `GET`, `POST`, `PUT`, `PATCH`, and `DELETE`
- route helpers currently exist for `GET` and `POST`
- the request head and body share one 8 KB accumulator
- request bodies require `Content-Length`
- a `GET` request with a body is rejected intentionally
- one request is handled per connection and the socket is closed after the response
- keep-alive, pipelining, TLS, and WebSockets are not implemented
- header names are currently stored as they arrive, so `Content-Length` is expected with this casing

```sh
odin run .
```

The server starts on `http://127.0.0.1:8080`.

Debug logging is disabled by default. I enable it at compile time when I want
to inspect connections, requests, headers, and completed sends:

```sh
odin run . -debug
```

## Try it

```sh
curl http://127.0.0.1:8080/pong             # 200 Pong
curl -X POST http://127.0.0.1:8080/ping     # 200 Ping
curl http://127.0.0.1:8080/ping             # 404, wrong method
```

