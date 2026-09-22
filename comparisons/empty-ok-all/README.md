# HTTP server comparison

This suite compares the repository's actual Odin HTTP server with equivalent
Go, Bun, Node.js, and Rust/Actix servers. There is no copied Odin server in
this directory.

Every server listens on `127.0.0.1:8080` and implements the same operation:

```text
GET /pong -> 200 OK
body: Pong
```

## Load generator

Use [codesenberg/bombardier](https://github.com/codesenberg/bombardier) for
every run. Its official installation options are a prebuilt release binary or:

```powershell
go install github.com/codesenberg/bombardier@latest
```

The Odin server currently closes each connection after responding. Send the
same header to every implementation so the comparison measures equivalent
connection behavior:

```powershell
bombardier -c 250 -n 100000 -H "Connection: close" http://127.0.0.1:8080/pong
```

After a short verification run, the reference-sized workload is:

```powershell
bombardier -c 250 -n 10000000 -H "Connection: close" http://127.0.0.1:8080/pong
```

Build and start only one server at a time. Run every server several times and
compare median requests per second. Use the same machine, power mode,
Bombardier command, and background workload, and record compiler/runtime
versions with the results.
