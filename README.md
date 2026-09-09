# odin-server

A minimal HTTP/1.1 server written from scratch in [Odin](https://odin-lang.org/), on raw TCP sockets. Learning project — no framework, nothing outside Odin's core library.

## What it does

- Parses the request line, headers, and a `Content-Length` body (8 KB total per request)
- Routes on method + path via `map[Route_Key]Handler`
- Handlers fill a `Response`; `build_response` serialises it and always answers — `400`, `404`, `408`, `413`, `431`, `501` on the failure paths
- 10 s receive timeout per connection, so a stalled client can't hang the process
- Wraps `context.allocator` in a tracking allocator for leak reporting

Methods: `GET`, `POST`, `PUT`, `PATCH`, `DELETE`.

## Biggest bottleneck

**One connection at a time.** `server_loop` accepts, serves, and closes before it looks at the next client — no threads, no polling, no queue. Throughput is capped at `1 / request_latency`, and any client that connects and then stalls blocks *every* other client for up to the full 10 s timeout. Opening sockets in a loop is enough to take it offline.

Fixing this means an event loop or a thread/connection pool, and it is the only change that would make the rest of the server worth optimising.

## Layout

```
main.odin           accept loop, request flow, error -> status mapping
routes/ping.odin    example handler
http/types.odin     Request, Response, method and error types
http/read.odin      reading the head and body off the socket
http/parse.odin     request line and header parsing
http/router.odin    route table, add_route / find_route
http/response.odin  response serialisation, send_error
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
