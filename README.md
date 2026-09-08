# odin-server

A minimal HTTP server written from scratch in [Odin](https://odin-lang.org/), built on raw TCP sockets. It's a learning project — no framework, no dependencies beyond Odin's core library.

## What it does

- Listens on `127.0.0.1:3000` and accepts TCP connections one at a time
- Reads and parses the request line (`METHOD PATH VERSION`)
- Parses headers into a `map[string]string`
- Reads the request body for `POST`/`PUT`/`PATCH` using `Content-Length`
- Logs everything it parsed

Supported methods: `GET`, `POST`, `PUT`, `PATCH`. Requests are capped at an 8 KB buffer. The server does not send responses back yet.

## Layout

```
main.odin        entry point: socket setup, accept loop, request handling
http/types.odin  Request struct, method and error enums
http/read.odin   reading the head and body off the socket
http/parse.odin  request line and header parsing
http/debug.odin  --debug flag and debug logging helpers
```

## Requirements

- [Odin compiler](https://odin-lang.org/docs/install/) on your `PATH`

## Run

```sh
odin run .
```

With debug logging:

```sh
odin run . -- -debug
```

Or build and run the binary:

```sh
odin build .
./odin-server -debug
```

## Try it

```sh
curl -X POST http://127.0.0.1:3000/hello -d "some body"
```
