import { decoders as d, request, type ApiResult, type Decoded } from "@/api";
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

export const invitationCases = [
  "new_account",
  "existing_account",
  "signed_in_match",
  "signed_in_other",
  "expired",
  "withdrawn",
  "accepted",
] as const;
/** Typing rule (1): a new server case reads as "unrecognized", never a failed page. */
export type InvitationCase = (typeof invitationCases)[number] | "unrecognized";
export const invitationRoles = ["member", "organization_admin"] as const;
export type InvitationRole = (typeof invitationRoles)[number] | "unrecognized";

const person = d.nullable(d.object({ id: d.nullable(d.string), name: d.nullable(d.string) }));
const invitationReader = d.object({
  case: d.known(invitationCases),
  organization: d.object({ id: d.token, name: d.string }),
  role: d.nullable(d.known(invitationRoles)),
  invited_by: person,
  invited_at: d.nullable(d.timestamp),
  email: d.string,
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
  organization: d.optional(d.object({ id: d.token, name: d.string })),
  role: d.optional(d.nullable(d.known(invitationRoles))),
  invited_by: d.optional(person),
  invited_at: d.optional(d.nullable(d.timestamp)),
  email: d.optional(d.string),
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
