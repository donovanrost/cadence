import { createReadStream } from "node:fs";
import { access, stat } from "node:fs/promises";
import { createServer, type ServerResponse } from "node:http";
import { extname, resolve, sep } from "node:path";
import { createDemoHostMiddleware } from "./demo-host-service.ts";

const frontendRoot = resolve(import.meta.dirname, "..");
const hostRoot = resolve(frontendRoot, "apps/host/dist");
const telemetryRoot = resolve(frontendRoot, "apps/telemetry-decom/dist");
const probeRoot = resolve(frontendRoot, "apps/contract-probe/dist");
const hostMiddleware = createDemoHostMiddleware("production");

await Promise.all([
  requireBuild(resolve(hostRoot, "index.html")),
  requireBuild(resolve(telemetryRoot, "current/mf-manifest.json")),
  requireBuild(resolve(telemetryRoot, "previous/mf-manifest.json")),
  requireBuild(resolve(probeRoot, "current/mf-manifest.json")),
]);

const host = createServer((request, response) => {
  void hostMiddleware(request, response, () => {
    const pathname = new URL(request.url ?? "/", "http://127.0.0.1:5173").pathname;
    const requestedPath = pathname === "/" ? "/index.html" : pathname;
    void serveStatic(response, hostRoot, requestedPath, {
      fallback: "/index.html",
      headers: {
        "content-security-policy": [
          "default-src 'self'",
          "script-src 'self' http://127.0.0.1:4174 http://127.0.0.1:4175 http://127.0.0.1:4199",
          "style-src 'self' 'unsafe-inline' http://127.0.0.1:4174 http://127.0.0.1:4175",
          "font-src 'self' data:",
          "connect-src 'self' http://127.0.0.1:4174 http://127.0.0.1:4175 http://127.0.0.1:4199",
          "img-src 'self' data:",
          "object-src 'none'",
          "base-uri 'self'",
          "frame-ancestors 'none'",
        ].join("; "),
        "x-content-type-options": "nosniff",
      },
    }).catch(() => serverError(response));
  });
});

const telemetry = createServer((request, response) => {
  const pathname = new URL(request.url ?? "/", "http://127.0.0.1:4174").pathname;
  const releasePath = releaseStaticPath(pathname);
  if (!releasePath) {
    notFound(response);
    return;
  }

  void serveStatic(response, telemetryRoot, releasePath, { headers: remoteHeaders() }).catch(() =>
    serverError(response),
  );
});

const probe = createServer((request, response) => {
  const pathname = new URL(request.url ?? "/", "http://127.0.0.1:4175").pathname;
  const releasePath = releaseStaticPath(pathname);
  if (!releasePath) {
    notFound(response);
    return;
  }

  void serveStatic(response, probeRoot, releasePath, { headers: remoteHeaders() }).catch(() =>
    serverError(response),
  );
});

await Promise.all([
  listen(host, 5173, "Cadence host"),
  listen(telemetry, 4174, "Telemetry Decom releases"),
  listen(probe, 4175, "Contract Probe release"),
]);

for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.on(signal, () => {
    host.close();
    telemetry.close();
    probe.close();
  });
}

function releaseStaticPath(pathname: string): string | undefined {
  const match = /^\/releases\/(current|previous)(\/.*)?$/.exec(pathname);
  if (!match) return undefined;
  return `/${match[1]}${match[2] ?? "/index.html"}`;
}

async function serveStatic(
  response: ServerResponse,
  root: string,
  requestPath: string,
  options: {
    fallback?: string;
    headers?: Readonly<Record<string, string>>;
  } = {},
): Promise<void> {
  const file = safeFile(root, requestPath);
  const target = (await regularFile(file))
    ? file
    : options.fallback && safeFile(root, options.fallback);

  if (!target || !(await regularFile(target))) {
    notFound(response);
    return;
  }

  const cacheControl = cacheHeader(target);
  response.writeHead(200, {
    "content-type": contentType(target),
    "cache-control": cacheControl,
    ...options.headers,
  });

  createReadStream(target).pipe(response);
}

function safeFile(root: string, requestPath: string): string {
  const decoded = decodeURIComponent(requestPath).replaceAll("\\", "/");
  const target = resolve(root, `.${decoded}`);
  if (target !== root && !target.startsWith(`${root}${sep}`)) {
    throw new Error("Static request escaped its configured root.");
  }
  return target;
}

async function regularFile(path: string): Promise<boolean> {
  try {
    return (await stat(path)).isFile();
  } catch {
    return false;
  }
}

function cacheHeader(path: string): string {
  if (path.endsWith("mf-manifest.json") || path.endsWith("index.html")) {
    return "no-store";
  }
  if (path.includes(`${sep}assets${sep}`)) return "public, max-age=31536000, immutable";
  if (/-[A-Z0-9]{8}\.(?:css|js)$/.test(path)) return "public, max-age=31536000, immutable";
  return "public, max-age=300";
}

function contentType(path: string): string {
  const types: Readonly<Record<string, string>> = {
    ".css": "text/css; charset=utf-8",
    ".html": "text/html; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".json": "application/json; charset=utf-8",
    ".map": "application/json; charset=utf-8",
    ".svg": "image/svg+xml",
    ".woff2": "font/woff2",
  };
  return types[extname(path)] ?? "application/octet-stream";
}

function remoteHeaders(): Readonly<Record<string, string>> {
  return {
    "access-control-allow-origin": "http://127.0.0.1:5173",
    "cross-origin-resource-policy": "cross-origin",
    "x-content-type-options": "nosniff",
  };
}

function notFound(response: ServerResponse): void {
  response.writeHead(404, { "content-type": "text/plain; charset=utf-8" });
  response.end("Not found");
}

function serverError(response: ServerResponse): void {
  if (response.headersSent) {
    response.destroy();
    return;
  }

  response.writeHead(500, { "content-type": "text/plain; charset=utf-8" });
  response.end("Internal server error");
}

async function requireBuild(path: string): Promise<void> {
  try {
    await access(path);
  } catch {
    throw new Error(`Missing production artifact: ${path}. Run vp run build first.`);
  }
}

function listen(
  server: ReturnType<typeof createServer>,
  port: number,
  label: string,
): Promise<void> {
  return new Promise((resolveListening, reject) => {
    server.once("error", reject);
    server.listen(port, "127.0.0.1", () => {
      process.stdout.write(`${label} listening on http://127.0.0.1:${port}\n`);
      resolveListening();
    });
  });
}
