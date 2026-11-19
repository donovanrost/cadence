import { decoders as d, request, role, type ApiResult, type Decoded } from "@/api";
import { fetchSession, type Session } from "@/api/session.ts";

/**
 * L5 public auth endpoints (api-ops' agreed shapes, BACKLOG §11 L5; ux Auth.md). Built against
 * fixtures; api-ops builds them after L6. CSRF comes from the served page's meta tag (`request`).
 */

const redirectReader = d.object({ redirect_to: d.string });

export function signIn(email: string, password: string, returnTo: string | null) {
  return request("/auth/sign-in", redirectReader, {
    method: "POST",
    body: { email, password, ...(returnTo ? { return_to: returnTo } : {}) },
  });
}

/** api-ops (L5): GET's cases; `used`, `declined` and `unavailable` also come as invitation_unavailable. */
export const invitationCases = [
  "new_account",
  "existing_account",
  "signed_in_match",
  "signed_in_other",
  "expired",
  "withdrawn",
  "accepted",
  "used",
  "declined",
  "unavailable",
  "unknown",
] as const;
/** Typing rule (1): a new server case reads as "unrecognized", never a failed page. */
export type InvitationCase = (typeof invitationCases)[number] | "unrecognized";

/** session.md L5: people and organizations come as `{name} | null` (no ids on this public read). */
const person = d.nullable(d.object({ name: d.nullable(d.string) }));
const org = d.nullable(d.object({ name: d.string }));
const invitationReader = d.object({
  case: d.known(invitationCases),
  organization: org,
  role: d.nullable(role),
  invited_by: person,
  invited_at: d.nullable(d.timestamp),
  email: d.nullable(d.string),
  expires_at: d.nullable(d.timestamp),
  /** Withdrawn: who withdrew it, when the server says (U29). */
  withdrawn_by: d.optional(person),
});
export type Invitation = Decoded<typeof invitationReader>;

/**
 * `invitation_unavailable` details (expired, withdrawn, accepted): what the server says about why;
 * every field but `case` may be missing.
 */
export const unavailableReader = d.object({
  case: d.known(invitationCases),
  organization: d.optional(org),
  role: d.optional(d.nullable(role)),
  invited_by: d.optional(person),
  invited_at: d.optional(d.nullable(d.timestamp)),
  email: d.optional(d.nullable(d.string)),
  expires_at: d.optional(d.nullable(d.timestamp)),
  withdrawn_by: d.optional(person),
});

const enc = encodeURIComponent;

export function fetchInvitation(
  token: string,
  signal?: AbortSignal,
): Promise<ApiResult<Invitation>> {
  return request(`/auth/invitations/${enc(token)}`, invitationReader, signal ? { signal } : {});
}

export type AcceptBody =
  | Readonly<{ kind: "new_account"; name: string; password: string }>
  | Readonly<{ kind: "existing_account"; password: string }>
  | Readonly<{ kind: "signed_in_match" }>;

const acceptReader = d.object({ organization_id: d.token, redirect_to: d.string });

export function acceptInvitation(token: string, body: AcceptBody) {
  return request(`/auth/invitations/${enc(token)}/accept`, acceptReader, {
    method: "POST",
    body,
  });
}

const nothing = d.nullable((value) => value);
export function declineInvitation(token: string) {
  return request(`/auth/invitations/${enc(token)}/decline`, nothing, { method: "POST", body: {} });
}

/**
 * The session if someone's signed in, else null (public routes: a 401 means anonymous, never a
 * redirect). Other failures are returned for the screen to say.
 */
export async function optionalSession(signal?: AbortSignal): Promise<ApiResult<Session | null>> {
  const r = await fetchSession(signal);
  if (r.ok || r.error.kind !== "unauthenticated") return r;
  return { ok: true, value: null };
}

/** `return_to` is honoured only as a same-origin path ("/…", never "//…"); else console home. */
export function safeReturn(raw: unknown): string | null {
  if (typeof raw !== "string" || !raw.startsWith("/") || raw.startsWith("//")) return null;
  return raw;
}

/** "Sign out and continue": ends the session, then reloads this page signed out. */
export async function signOutHere(csrf: string | null): Promise<void> {
  await fetch("/session", {
    method: "DELETE",
    credentials: "same-origin",
    redirect: "manual",
    headers: csrf ? { "x-csrf-token": csrf } : {},
  });
  window.location.reload();
}

/** A full navigation: the csrf token changes after sign-in, and the server validated the target. */
export const goTo = (url: string) => window.location.assign(url);
