import type { Page } from "@playwright/test";

const READS = new Set(["GET", "HEAD", "OPTIONS"]);

/**
 * What the console sends on its Phoenix socket: the channel protocol, and the opt-in
 * subscriptions that ask for pushes (no write). Anything else is blocked.
 */
const SOCKET_READS = new Set([
  "phx_join",
  "phx_leave",
  "heartbeat",
  "view:subscribe",
  "view:set",
  "view:unsubscribe",
  "fleet:subscribe",
  "fleet:unsubscribe",
  "points:set",
]);

/** A Phoenix V2 frame from the client: `[join_ref, ref, topic, event, payload]`. */
function socketEvent(message: string | Buffer): string | null {
  if (typeof message !== "string") return null;
  try {
    const frame: unknown = JSON.parse(message);
    return Array.isArray(frame) && typeof frame[3] === "string" ? frame[3] : null;
  } catch {
    return null;
  }
}

/**
 * The a11y passes run read-only on the shared dev stack (qa's :4011 condition):
 * - every HTTP request other than a read is aborted at the route, so nothing reaches the server;
 * - on the Phoenix socket, only the channel protocol and the read subscriptions above are passed
 *   on; any other client message is dropped. The server's messages pass unchanged.
 * Each blocked request or message is logged as "a11y read-only: blocked …" for qa's report. HTTP
 * aborts use "aborted", which the diagnostics fixture ignores like a request a navigation cut off.
 */
export async function guardReadOnly(page: Page): Promise<void> {
  await page.route("**/*", async (route) => {
    const request = route.request();
    if (READS.has(request.method())) return route.fallback();
    console.log(`a11y read-only: blocked ${request.method()} ${new URL(request.url()).pathname}`);
    return route.abort("aborted");
  });
  await page.routeWebSocket(
    (url) => url.pathname.endsWith("/websocket"),
    (ws) => {
      const server = ws.connectToServer();
      ws.onMessage((message) => {
        const event = socketEvent(message);
        if (event !== null && SOCKET_READS.has(event)) return server.send(message);
        console.log(`a11y read-only: blocked socket message ${event ?? "(not a channel frame)"}`);
      });
      server.onMessage((message) => ws.send(message));
    },
  );
}
