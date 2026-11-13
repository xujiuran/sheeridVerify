// 容器内的本机回环反代。
//
// 上游服务只接受 Host 为 127.0.0.1:<port> / localhost:<port> 的请求（防 DNS rebinding），
// 而容器需要监听 0.0.0.0 才能被宿主机访问。这里在 0.0.0.0:8787 收请求，改写 Host 后
// 转发给 127.0.0.1:8788，并对写请求去掉 Origin 头——Origin 校验只用于判断「是否同源」，
// 容器内上游与浏览器已不同源，保留原文会被判 403。
import { createServer, request as httpRequest } from 'node:http';

const LISTEN_PORT = Number(process.env.PROXY_PORT ?? 8787);
const UPSTREAM_PORT = Number(process.env.APP_PORT ?? 8788);
const UPSTREAM_HOST = '127.0.0.1';
const UPSTREAM_HOST_HEADER = `${UPSTREAM_HOST}:${UPSTREAM_PORT}`;

const server = createServer((clientRequest, clientResponse) => {
  const headers = { ...clientRequest.headers, host: UPSTREAM_HOST_HEADER };
  // 上游会比对 Origin 与自身地址；跨端访问时该头必然不等，直接不传。
  delete headers.origin;

  const upstream = httpRequest(
    { host: UPSTREAM_HOST, port: UPSTREAM_PORT, method: clientRequest.method, path: clientRequest.url, headers },
    upstreamResponse => {
      clientResponse.writeHead(upstreamResponse.statusCode ?? 502, upstreamResponse.headers);
      upstreamResponse.pipe(clientResponse);
    },
  );

  upstream.on('error', error => {
    if (clientResponse.headersSent) {
      clientResponse.destroy();
      return;
    }
    clientResponse.writeHead(502, { 'Content-Type': 'application/json; charset=utf-8' });
    clientResponse.end(JSON.stringify({ error: { code: 'UPSTREAM_UNAVAILABLE', message: `上游服务未就绪：${error.message}` } }));
  });

  clientRequest.pipe(upstream);
});

server.requestTimeout = 120000;
server.listen(LISTEN_PORT, '0.0.0.0', () => {
  process.stdout.write(`本机反代已启动：http://0.0.0.0:${LISTEN_PORT} -> ${UPSTREAM_HOST_HEADER}\n`);
});

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.once(signal, () => server.close(() => process.exit(0)));
}
