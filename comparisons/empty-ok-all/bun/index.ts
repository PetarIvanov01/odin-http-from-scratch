const server = Bun.serve({
  hostname: "127.0.0.1",
  port: 8080,
  fetch(request) {
    const url = new URL(request.url);

    if (request.method !== "GET" || url.pathname !== "/pong") {
      return new Response(null, { status: 404 });
    }

    return new Response("Pong", {
      status: 200,
      headers: { "Content-Type": "text/plain" },
    });
  },
});

console.log(`Bun server listening on ${server.url}`);
