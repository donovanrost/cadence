import { createHash, randomUUID, timingSafeEqual } from "node:crypto";
import type { IncomingMessage, ServerResponse } from "node:http";
import type { DemoMode, DemoRequest, DemoResponse } from "./demo-host-service";

const sessionPath = "/api/cadence/session";
const sessionCookie = "cadence_frontend_session";

export interface DemoAdminCredentials {
  displayName: string;
  email: string;
  password: string;
  ttlSeconds: number;
}

interface DemoAdminSession {
  expiresAt: number;
  session: FrontendSession;
}

export interface FrontendSession {
  schema: "cadence.frontend-session.v1";
  actor: {
    displayName: string;
    email: string;
  };
  authority: {
    role: "platform_admin";
    adminModeExpiresAt: string;
  };
  environment: {
    mode: DemoMode;
    name: string;
  };
}

export class DemoAuthService {
  readonly #credentials: DemoAdminCredentials;
  readonly #mode: DemoMode;
  readonly #sessions = new Map<string, DemoAdminSession>();

  constructor(mode: DemoMode, credentials: DemoAdminCredentials = environmentCredentials()) {
    this.#mode = mode;
    this.#credentials = credentials;
  }

  handle(request: DemoRequest): DemoResponse | undefined {
    const url = new URL(request.url, "http://127.0.0.1:5173");
    if (url.pathname !== sessionPath) return undefined;

    if (request.method === "GET") return this.#currentSession(request);
    if (request.method === "POST") return this.#createSession(request);
    if (request.method === "DELETE") return this.#deleteSession(request);

    return problem(405, "method_not_allowed", "The session endpoint does not support that method.");
  }

  #currentSession(request: DemoRequest): DemoResponse {
    const session = this.#resolveSession(request);
    return session
      ? json(200, session.session, { "cache-control": "no-store" })
      : { status: 204, headers: { "cache-control": "no-store" }, body: null };
  }

  #createSession(request: DemoRequest): DemoResponse {
    const body = request.body;
    if (!isRecord(body) || typeof body.email !== "string" || typeof body.password !== "string") {
      return problem(400, "invalid_credentials", "Enter both email and password.");
    }

    const validEmail = secureEqual(body.email.trim().toLowerCase(), this.#credentials.email);
    const validPassword = secureEqual(body.password, this.#credentials.password);
    if (!validEmail || !validPassword) {
      return problem(401, "invalid_credentials", "The supplied email or password was rejected.");
    }

    const sessionId = randomUUID();
    const expiresAt = Date.now() + this.#credentials.ttlSeconds * 1_000;
    const session: FrontendSession = {
      schema: "cadence.frontend-session.v1",
      actor: {
        displayName: this.#credentials.displayName,
        email: this.#credentials.email,
      },
      authority: {
        role: "platform_admin",
        adminModeExpiresAt: new Date(expiresAt).toISOString(),
      },
      environment: {
        mode: this.#mode,
        name: this.#mode === "development" ? "Local development" : "PoC preview",
      },
    };
    this.#sessions.set(sessionId, { expiresAt, session });

    return json(201, session, {
      "cache-control": "no-store",
      "set-cookie": `${sessionCookie}=${sessionId}; HttpOnly; SameSite=Lax; Path=/; Max-Age=${this.#credentials.ttlSeconds}`,
    });
  }

  #deleteSession(request: DemoRequest): DemoResponse {
    const sessionId = cookie(request.headers?.cookie, sessionCookie);
    if (sessionId) this.#sessions.delete(sessionId);

    return json(
      200,
      { signedOut: true },
      {
        "cache-control": "no-store",
        "set-cookie": `${sessionCookie}=; HttpOnly; SameSite=Lax; Path=/; Max-Age=0`,
      },
    );
  }

  #resolveSession(request: DemoRequest): DemoAdminSession | undefined {
    const sessionId = cookie(request.headers?.cookie, sessionCookie);
    if (!sessionId) return undefined;

    const session = this.#sessions.get(sessionId);
    if (!session) return undefined;

    if (session.expiresAt <= Date.now()) {
      this.#sessions.delete(sessionId);
      return undefined;
    }

    return session;
  }
}

export function createDemoAuthMiddleware(mode: DemoMode) {
  const service = new DemoAuthService(mode);

  return async function demoAuthMiddleware(
    request: IncomingMessage,
    response: ServerResponse,
    next: () => void,
  ): Promise<void> {
    const url = request.url ?? "/";
    if (!url.startsWith(sessionPath)) {
      next();
      return;
    }

    let body: unknown;
    if (request.method === "POST") {
      try {
        body = JSON.parse(await requestBody(request));
      } catch {
        writeResponse(
          response,
          problem(400, "invalid_json", "The request body is not valid JSON."),
        );
        return;
      }
    }

    const result = service.handle({
      method: request.method ?? "GET",
      url,
      headers: normalizeHeaders(request.headers),
      body,
    });

    if (!result) {
      next();
      return;
    }

    writeResponse(response, result);
  };
}

function environmentCredentials(): DemoAdminCredentials {
  return {
    displayName: process.env.CADENCE_ADMIN_DISPLAY_NAME ?? "Cadence Administrator",
    email: (process.env.CADENCE_ADMIN_EMAIL ?? "admin@example.com").trim().toLowerCase(),
    password: process.env.CADENCE_ADMIN_PASSWORD ?? "change-me",
    ttlSeconds: positiveInteger(process.env.CADENCE_ADMIN_MODE_TTL_SECONDS, 3_600),
  };
}

function positiveInteger(value: string | undefined, fallback: number): number {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : fallback;
}

function secureEqual(left: string, right: string): boolean {
  const leftDigest = createHash("sha256").update(left).digest();
  const rightDigest = createHash("sha256").update(right).digest();
  return timingSafeEqual(leftDigest, rightDigest);
}

function cookie(header: string | undefined, name: string): string | undefined {
  return header
    ?.split(";")
    .map((part) => part.trim().split("=", 2))
    .find(([candidate]) => candidate === name)?.[1];
}

function json(
  status: number,
  body: unknown,
  headers: Readonly<Record<string, string>> = {},
): DemoResponse {
  return {
    status,
    headers: { "content-type": "application/json; charset=utf-8", ...headers },
    body,
  };
}

function problem(status: number, code: string, message: string): DemoResponse {
  return json(status, { schema: "cadence.frontend-session-problem.v1", code, message });
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

async function requestBody(request: IncomingMessage): Promise<string> {
  const chunks: Uint8Array[] = [];
  for await (const chunk of request) {
    chunks.push(typeof chunk === "string" ? Buffer.from(chunk) : chunk);
  }
  return Buffer.concat(chunks).toString("utf8");
}

function normalizeHeaders(headers: IncomingMessage["headers"]): Record<string, string | undefined> {
  return Object.fromEntries(
    Object.entries(headers).map(([name, value]) => [
      name.toLowerCase(),
      Array.isArray(value) ? value.join(", ") : value,
    ]),
  );
}

function writeResponse(response: ServerResponse, result: DemoResponse): void {
  response.writeHead(result.status, result.headers);
  response.end(JSON.stringify(result.body));
}
