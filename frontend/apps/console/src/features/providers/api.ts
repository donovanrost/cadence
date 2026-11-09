import { decoders, request, type ApiResult, type Decoded } from "@/api";
import type { OpState } from "@/ui";

/** Contract: docs/apogee/api/setup.md, `GET /organizations/:id/provider-accounts` (PA1). */
const { array, nullable, object, oneOf, string, timestamp, token } = decoders;

const account = object({
  id: token,
  name: string,
  provider: object({ key: token, label: string }),
  status: oneOf(["connected", "expiring", "auth_failed", "not_checked"]),
  status_detail: nullable(string),
  expires_at: nullable(timestamp),
  last_success_at: nullable(timestamp),
  missions: array(object({ id: token, name: string }), 500),
  added_at: timestamp,
  added_by: nullable(object({ name: string })),
});
export const accountsReader = object({
  accounts: array(account, 500),
  adapters: array(object({ key: token, label: string }), 100),
  permissions: array(token, 50),
});
export type ProviderAccount = Decoded<typeof account>;
export type ProviderAccounts = Decoded<typeof accountsReader>;

export function fetchProviderAccounts(
  organizationId: string,
  signal: AbortSignal,
): Promise<ApiResult<ProviderAccounts>> {
  return request(
    `/organizations/${encodeURIComponent(organizationId)}/provider-accounts`,
    accountsReader,
    { signal },
  );
}

/** The real credential check: the reference resolves and the provider accepts it. */
export function testAccount(
  organizationId: string,
  accountId: string,
): Promise<ApiResult<{ ok: boolean; message: string }>> {
  return request(
    `/organizations/${encodeURIComponent(organizationId)}/provider-accounts/${encodeURIComponent(accountId)}/test`,
    object({ ok: decoders.boolean, message: string }),
    { method: "POST", body: {} },
  );
}

/** Status is real only: not checked is its own (stale-hatched) state, never "connected". */
export function statusTag(a: ProviderAccount): { state: OpState; label: string } {
  switch (a.status) {
    case "connected":
      return { state: "nominal", label: "Connected" };
    case "expiring":
      return { state: "caution", label: "Credentials expiring" };
    case "auth_failed":
      return { state: "crit", label: "Auth failed" };
    case "not_checked":
      return { state: "stale", label: "Not checked" };
  }
}
