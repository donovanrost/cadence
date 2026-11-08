import { decode, object, optional, string, token, type Reader } from "./decode.ts";

/** Base path of the session-authenticated console JSON API. */
export const API_BASE = "/api/console/v1";

export type ApiError =
  | { kind: "unauthenticated" }
  | { kind: "forbidden"; message: string }
  | { kind: "not_found"; message: string }
  | { kind: "conflict"; code: string; message: string; details: unknown }
  | { kind: "invalid"; message: string; details: unknown }
  | { kind: "unavailable"; status: number; message: string }
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
      return { kind: "forbidden", message };
    case 404:
      return { kind: "not_found", message };
    case 409:
      return { kind: "conflict", code, message, details };
    case 400:
    case 422:
      return { kind: "invalid", message, details };
    default:
      return { kind: "unavailable", status, message };
  }
}

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
  if (options.body !== undefined) headers["content-type"] = "application/json";
  const csrf = currentCsrfToken();
  if (method !== "GET" && csrf) headers["x-csrf-token"] = csrf;

  let response: Response;
  try {
    response = await fetch(`${API_BASE}${path}`, {
      method,
      headers,
      credentials: "same-origin",
      ...(options.body === undefined ? {} : { body: JSON.stringify(options.body) }),
      ...(options.signal ? { signal: options.signal } : {}),
    });
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") throw error;
    return { ok: false, error: { kind: "unavailable", status: 0, message: "Network unreachable" } };
  }

  const body = await readJson(response);
  if (!response.ok) return { ok: false, error: toError(response.status, body) };
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
