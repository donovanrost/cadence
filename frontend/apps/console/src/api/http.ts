import { decode, object, optional, string, token, type Reader } from "./decode.ts";

/** Base path of the session-authenticated console JSON API. */
export const API_BASE = "/api/console/v1";

export type ApiError =
  | { kind: "unauthenticated" }
  | { kind: "forbidden"; code: string; message: string }
  | { kind: "not_found"; code: string; message: string }
  | { kind: "conflict"; code: string; message: string; details: unknown }
  | { kind: "invalid"; code: string; message: string; details: unknown }
  /**
   * `serverCode`: the server's error code when it answered with an error envelope (e.g. 503
   * `apply_interrupted`). Not `code`, so `"code" in error` keeps meaning a 4xx-style refusal.
   */
  | { kind: "unavailable"; status: number; message: string; serverCode?: string | undefined }
  | { kind: "malformed"; message: string };

export type ApiResult<T> = { ok: true; value: T } | { ok: false; error: ApiError };

const errorBody = object({
  error: object({ code: token, message: string, details: optional((value) => value) }),
});

let csrfToken: string | null = null;

/** Set once the session bootstrap resolves; the served index also carries it in a meta tag. */
export function setCsrfToken(value: string) {
  csrfToken = value;
}

function currentCsrfToken(): string | null {
  if (csrfToken) return csrfToken;
  const meta = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]');
  return meta?.content || null;
}

type Method = "GET" | "POST" | "PUT" | "PATCH" | "DELETE";

export type RequestOptions = Readonly<{
  method?: Method;
  body?: unknown;
  signal?: AbortSignal;
}>;

async function readJson(response: Response): Promise<unknown> {
  const text = await response.text();
  if (text === "") return null;
  try {
    return JSON.parse(text) as unknown;
  } catch {
    return undefined;
  }
}

function toError(status: number, body: unknown): ApiError {
  const parsed = decode(errorBody, body);
  const code = parsed.ok ? parsed.value.error.code : `http_${status}`;
  const message = parsed.ok ? parsed.value.error.message : `Request failed (${status})`;
  const details = parsed.ok ? parsed.value.error.details : undefined;
  switch (status) {
    case 401:
      return { kind: "unauthenticated" };
    case 403:
      return { kind: "forbidden", code, message };
    case 404:
      return { kind: "not_found", code, message };
    case 409:
      return { kind: "conflict", code, message, details };
    case 413:
      return {
        kind: "invalid",
        code: parsed.ok ? code : "file_too_large",
        message: parsed.ok ? message : "That file is too large to upload.",
        details,
      };
    case 400:
    case 422:
      return { kind: "invalid", code, message, details };
    default:
      return parsed.ok
        ? { kind: "unavailable", status, message, serverCode: code }
        : { kind: "unavailable", status, message };
  }
}

/**
 * True when a write's outcome is unknown: the reply was unreadable, the connection dropped, or the
 * server failed while answering (5xx). The write may have committed (qa #19: a 500 after a
 * committed apply), so say "unclear, check now", never "nothing changed".
 */
export function outcomeUnknown(error: ApiError): boolean {
  if (error.kind === "unavailable" && error.serverCode && SETTLED.has(error.serverCode))
    return false;
  return (
    error.kind === "malformed" ||
    (error.kind === "unavailable" && (error.status === 0 || error.status >= 500))
  );
}

/**
 * 5xx codes whose server has confirmed the outcome, so their own message is the answer:
 * `apply_interrupted` = the change did NOT land (domain 33529f29, api: "Try again.").
 */
const SETTLED: ReadonlySet<string> = new Set(["apply_interrupted"]);

/**
 * Calls a console API path (relative to API_BASE) and decodes the `data` member of a
 * successful response with `read`. Network failures and non-2xx responses become ApiError;
 * nothing undecoded leaves this function. Aborts propagate as AbortError rejections.
 */
export async function request<T>(
  path: string,
  read: Reader<T>,
  options: RequestOptions = {},
): Promise<ApiResult<T>> {
  const method = options.method ?? "GET";
  const headers: Record<string, string> = { accept: "application/json" };
  // FormData goes as-is so the browser sets the multipart boundary; anything else is JSON.
  const multipart = options.body instanceof FormData;
  if (options.body !== undefined && !multipart) headers["content-type"] = "application/json";
  const csrf = currentCsrfToken();
  if (method !== "GET" && csrf) headers["x-csrf-token"] = csrf;

  let response: Response;
  try {
    response = await fetch(`${API_BASE}${path}`, {
      method,
      headers,
      credentials: "same-origin",
      ...(options.body === undefined
        ? {}
        : { body: options.body instanceof FormData ? options.body : JSON.stringify(options.body) }),
      ...(options.signal ? { signal: options.signal } : {}),
    });
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") throw error;
    return { ok: false, error: { kind: "unavailable", status: 0, message: "Network unreachable" } };
  }

  const body = await readJson(response);
  if (!response.ok) return { ok: false, error: toError(response.status, body) };
  // 204 No Content (e.g. DELETE /invitations/:id): no envelope; the reader decides what null means.
  if (response.status === 204) {
    const empty = decode(read, null);
    return empty.ok
      ? { ok: true, value: empty.value }
      : { ok: false, error: { kind: "malformed", message: empty.error.message } };
  }
  const envelope = decode(object({ data: read }), body);
  if (!envelope.ok)
    return { ok: false, error: { kind: "malformed", message: envelope.error.message } };
  return { ok: true, value: envelope.value.data };
}

/** Human sentence for an ApiError, for callouts and empty states. */
export function describeApiError(error: ApiError): string {
  switch (error.kind) {
    case "unauthenticated":
      return "Your session has ended. Sign in again.";
    case "forbidden":
    case "not_found":
    case "conflict":
    case "invalid":
    case "unavailable":
      return error.message;
    case "malformed":
      return `The server sent data this console does not understand (${error.message}).`;
  }
}
