'use strict';

const http = require('node:http');

const server = http.createServer((request, response) => {
  if (request.method !== 'GET' || request.url !== '/pong') {
    response.writeHead(404, { 'Content-Length': '0' });
    response.end();
    return;
  }

  response.writeHead(200, {
    'Content-Length': '4',
    'Content-Type': 'text/plain',
  });
  response.end('Pong');
});

server.listen(8080, '127.0.0.1', () => {
  console.log('Node server listening on http://127.0.0.1:8080');
});
