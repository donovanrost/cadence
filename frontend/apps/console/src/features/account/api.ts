import { fieldErrors, isError } from "@/api";
import {
  decoders as d,
  request,
  type ApiError,
  type ApiResult,
  type Decoded,
  outcomeUnknown,
} from "@/api";

/** Account: password and sessions (api session.md "Account"). The signed-in user's own account. */
export const sessionsReader = d.object({
  sessions: d.array(
    d.object({ id: d.token, started_at: d.timestamp, expires_at: d.timestamp, current: d.boolean }),
    500,
  ),
});
export type AccountSessions = Decoded<typeof sessionsReader>;
export type AccountSession = AccountSessions["sessions"][number];

export function changePassword(
  body: Readonly<{ current_password: string; new_password: string }>,
): Promise<ApiResult<null>> {
  return request("/account/password", () => null, { method: "PUT", body });
}

export function fetchSessions(
  _key: true,
  signal: AbortSignal,
): Promise<ApiResult<AccountSessions>> {
  return request("/account/sessions", sessionsReader, { signal });
}

export function signOutSession(id: string): Promise<ApiResult<null>> {
  return request(`/account/sessions/${encodeURIComponent(id)}`, () => null, { method: "DELETE" });
}

export function signOutOthers(): Promise<ApiResult<{ revoked: number }>> {
  return request("/account/sessions", d.object({ revoked: d.integer }), { method: "DELETE" });
}

export const PASSWORD_MIN = 12;

/** Client checks before sending (the server re-validates). Keyed by field. */
export function passwordProblems(
  current: string,
  next: string,
  confirm: string,
): Record<string, string> {
  const out: Record<string, string> = {};
  if (!current) out["current"] = "Enter your current password.";
  if (next.length < PASSWORD_MIN) out["next"] = `Use at least ${PASSWORD_MIN} characters.`;
  else if (next === current) out["next"] = "Choose a password different from the current one.";
  if (confirm !== next) out["confirm"] = "The two new passwords don't match.";
  return out;
}

/** Password errors: inline where they belong; U20 on a dropped connection. */
export function passwordFailure(
  e: ApiError,
): Readonly<{ text: string | null; fields: Record<string, string> }> {
  if (isError(e, "current_password_incorrect"))
    return { text: null, fields: { current: "That isn't your current password." } };
  if (isError(e, "password_managed_externally"))
    return {
      text: "Your password is managed by this environment's configuration, so it can't be changed here.",
      fields: {},
    };
  const next = fieldErrors(e)["new_password"];
  if (next) return { text: null, fields: { next } };
  if (outcomeUnknown(e))
    return {
      text: "No clear answer from the server, so your password may or may not have changed. Try signing in with the new one in another window before changing it again.",
      fields: {},
    };
  return {
    text: `Your password didn't change. ${"message" in e ? e.message : ""}`.trim(),
    fields: {},
  };
}
