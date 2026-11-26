import type { OrganizationId } from "@/api/index.ts";
import {
  actor,
  decoders as d,
  isError,
  orNull,
  request,
  type ApiError,
  type Decoded,
  type Reader,
} from "@/api";
import { failureOutcome } from "@/features/changes/index.ts";
import { plural } from "@/ui";

/**
 * L13 provider-account grants and credential revoke (plans/providers.md, proposed to api-ops
 * 11-13). Org admins only (:manage_provider_accounts). Expected versions stand in for the
 * LiveView's evidence map; the server rebuilds it.
 */
const path = (orgId: OrganizationId, accountId: string) =>
  `/organizations/${encodeURIComponent(orgId)}/provider-accounts/${encodeURIComponent(accountId)}`;

const raw: Reader<unknown> = (value) => value;

/**
 * Off until api-ops serves PA2 (plans/providers.md): reading a route the server doesn't have logs a
 * 404 on a live page (qa: it trips the e2e diagnostics guard). Flip when it lands.
 */
export const PA2_LIVE = true;

const grant = d.object({
  id: d.token,
  version: d.integer,
  mission: d.object({ id: d.token, name: d.string }),
  state: d.known(["active", "revoked"] as const),
  allowed_services: d.nullable(d.array(d.string, 500)),
  allowed_stations: d.nullable(d.array(d.string, 500)),
  max_quota: d.nullable(d.integer),
  // free-text: the reason the admin gave when granting it.
  reason: d.nullable(d.string),
  granted_by: orNull(actor),
  granted_at: d.timestamp,
  revoked_by: orNull(actor),
  revoked_at: d.nullable(d.timestamp),
  // free-text: the reason given when revoking it.
  revoke_reason: d.nullable(d.string),
});
export type AccountGrant = Decoded<typeof grant>;

/** PA2: the account's version, credential, guardrails and grants. */
const detailReader = d.object({
  account: d.object({
    id: d.token,
    version: d.integer,
    credential: d.object({
      // free-text: a masked secret reference, shown as is; never the secret.
      ref: d.string,
      /** null only when status is 'missing' (api-ops drift sweep). */
      version: d.nullable(d.integer),
      // 'missing': no credential is registered under the reference (accounts made unvalidated).
      status: d.known(["active", "revoked", "missing"] as const),
    }),
    /** null = no restriction on the account (api-ops 74ad20816). */
    guardrails: d.object({
      allowed_services: d.nullable(d.array(d.string, 500)),
      allowed_stations: d.nullable(d.array(d.string, 500)),
    }),
  }),
  grants: d.array(grant, 500),
  permissions: d.array(d.known(["provider_accounts.manage"] as const), 10),
});
export type AccountDetail = Decoded<typeof detailReader>;
export type AccountKey = Readonly<{ orgId: OrganizationId; accountId: string }>;
export function fetchAccountDetail(k: AccountKey, signal: AbortSignal) {
  return request(path(k.orgId, k.accountId), detailReader, { signal });
}

export type GrantBody = Readonly<{
  mission_id: string;
  allowed_stations?: readonly string[];
  max_quota?: number;
  reason?: string;
  expected_account_version: number;
}>;
export function grantToMission(k: AccountKey, body: GrantBody) {
  return request(`${path(k.orgId, k.accountId)}/grants`, d.object({ grant }), {
    method: "POST",
    body,
  });
}
export function revokeGrant(k: AccountKey, g: AccountGrant, reason: string) {
  return request(
    `${path(k.orgId, k.accountId)}/grants/${encodeURIComponent(g.id)}/revoke`,
    d.object({ grant, flagged_reservations: d.integer }),
    { method: "POST", body: { reason, expected_grant_version: g.version } },
  );
}
export function revokeCredential(k: AccountKey, credentialVersion: number, reason: string) {
  return request(`${path(k.orgId, k.accountId)}/credential/revoke`, d.object({ account: raw }), {
    method: "POST",
    body: { reason, expected_credential_version: credentialVersion },
  });
}

/** After revoking a grant: what happened to bookings that used it. */
export const revokedLine = (flagged: number) =>
  flagged === 0
    ? "Revoked. No open bookings used it."
    : `Revoked. ${plural(flagged, "open booking")} now need an operator's review.`;

/** "Stations SVB, NLT · quota 40" or "Everything the account allows". */
export function restrictionText(g: AccountGrant): string {
  const parts = [
    g.allowed_stations?.length ? `Stations ${g.allowed_stations.join(", ")}` : null,
    g.allowed_services?.length ? `Services ${g.allowed_services.join(", ")}` : null,
    g.max_quota !== null ? `quota ${g.max_quota}` : null,
  ].filter(Boolean);
  return parts.length > 0 ? parts.join(" · ") : "Everything the account allows";
}

/** One sentence for a refused write (U20). */
export function accountFailure(error: ApiError): string {
  if (isError(error, "account_changed"))
    return "This account changed since you loaded it. Reload and try again.";
  if (isError(error, "account_archived"))
    return "This account is archived, so it can't be granted.";
  if (isError(error, "grant_changed"))
    return "That grant changed since you loaded it. Reload to see it.";
  if (isError(error, "grant_already_revoked")) return "That grant is already revoked.";
  if (isError(error, "account_grant_not_found"))
    return "That grant isn't on this account any more.";
  if (isError(error, "credential_changed"))
    return "The credential changed since you loaded it. Reload to see it.";
  if (isError(error, "credential_already_revoked")) return "The credential is already revoked.";
  return failureOutcome(error, "changed").sentence;
}
