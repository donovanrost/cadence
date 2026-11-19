import { actor, decoders, recordOf, request, type ApiResult, type Decoded } from "@/api";
import { schemaFieldReader, type KindSchema } from "@/features/changes/index.ts";
import type { OpState } from "@/ui";
import { ingestionModes } from "./ingestion.ts";

/** Contract: docs/apogee/api/setup.md, `GET /organizations/:id/provider-accounts` (PA1). */
const { array, integer, nullable, object, string, timestamp, token } = decoders;

const account = object({
  id: token,
  name: string,
  provider: object({ key: token, label: string }),
  // known: one new status mustn't fail the whole list (api-ops L13 adds credential_revoked).
  status: decoders.known([
    "connected",
    "expiring",
    "auth_failed",
    "credential_revoked",
    "not_checked",
  ] as const),
  status_detail: nullable(string),
  expires_at: nullable(timestamp),
  last_success_at: nullable(timestamp),
  missions: array(object({ id: token, name: string }), 500),
  added_at: timestamp,
  added_by: nullable(actor),
  /** The current version's event ingestion mode (api-ops, 11-16); absent on older reads. */
  event_ingestion_mode: decoders.optional(nullable(decoders.knownText(ingestionModes))),
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

/** What a credential test verified or failed on (setup.md): the reference, later the provider. */
const testParts = ["reference", "provider"] as const;
const testReader = object({
  ok: decoders.boolean,
  checked: array(decoders.knownText(testParts), 10),
  failed: decoders.optional(nullable(decoders.knownText(testParts))),
  reason: decoders.optional(nullable(string)),
  message: string,
});
export type TestResult = Decoded<typeof testReader>;
const base = (orgId: string) => `/organizations/${encodeURIComponent(orgId)}`;
const accountPath = (orgId: string, id: string) =>
  `${base(orgId)}/provider-accounts/${encodeURIComponent(id)}`;

/** Checks the credential reference resolves; `checked` says what was verified (not the provider yet). */
export function testAccount(orgId: string, accountId: string): Promise<ApiResult<TestResult>> {
  return request(`${accountPath(orgId, accountId)}/test`, testReader, { method: "POST", body: {} });
}

/** ux: never "Connected" unless the provider itself was checked. */
export function testSentence(r: TestResult): { tone: "nominal" | "info" | "crit"; text: string } {
  if (!r.ok)
    return {
      tone: "crit",
      text:
        r.failed === "reference"
          ? `Reference not found in its secret store. ${r.message}`
          : r.failed === "provider"
            ? `The provider rejected the credential. ${r.message}`
            : r.message,
    };
  return r.checked.includes("provider")
    ? { tone: "nominal", text: `Connected. ${r.message}` }
    : {
        tone: "info",
        text: "Reference found · the provider wasn't contacted (provider sign-in checks aren't available yet).",
      };
}

/** `{key, fields}` (kind-schema fields), read as a KindSchema named after the adapter. */
export async function fetchAdapterSchema(
  key: Readonly<{ orgId: string; adapter: string }>,
  signal: AbortSignal,
): Promise<ApiResult<KindSchema>> {
  const result = await request(
    `${base(key.orgId)}/provider-adapters/${encodeURIComponent(key.adapter)}/schema`,
    object({ key: token, fields: array(schemaFieldReader, 100) }),
    { signal },
  );
  return result.ok
    ? { ok: true, value: { kind: result.value.key, fields: result.value.fields } }
    : result;
}

export type Credential = Readonly<{ backend: string; key: string }>;
const written = object({ id: token, version: nullable(integer) });

export function createAccount(
  orgId: string,
  body: Readonly<{
    provider_key: string;
    name: string;
    settings: Readonly<Record<string, unknown>>;
    credential: Credential;
  }>,
): Promise<ApiResult<Decoded<typeof written>>> {
  return request(`${base(orgId)}/provider-accounts`, written, { method: "POST", body });
}

/** A new version for settings/credential; a rename alone writes no version (version null). */
export function updateAccount(
  orgId: string,
  id: string,
  body: Readonly<{
    name?: string;
    settings?: Readonly<Record<string, unknown>>;
    credential?: Credential;
  }>,
): Promise<ApiResult<Decoded<typeof written>>> {
  return request(accountPath(orgId, id), written, { method: "PUT", body });
}

export function removeAccount(orgId: string, id: string): Promise<ApiResult<unknown>> {
  return request(accountPath(orgId, id), (v) => v, { method: "DELETE", body: {} });
}

/** 422 `details` keyed by field path ("credential.key", "settings.base_url", "name"). */
export function fieldErrors(details: unknown): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(recordOf(details) ?? {})) {
    const text = Array.isArray(v) ? v.filter((x) => typeof x === "string").join(" ") : v;
    if (typeof text === "string" && text) out[k.replace(/^settings\./, "")] = text;
  }
  return out;
}

/** Status is real only: not checked is its own (stale-hatched) state, never "connected". */
export function statusTag(a: ProviderAccount): { state: OpState; label: string } {
  switch (a.status) {
    case "connected":
      // The server's check only resolves the reference today (ux): never claim the provider. With a
      // last successful call, that column carries the contact (ux §7 #10).
      return {
        state: "off",
        label: a.last_success_at ? "Reference OK" : "Reference OK · provider not contacted",
      };
    case "expiring":
      return { state: "caution", label: "Credentials expiring" };
    case "auth_failed":
      return { state: "crit", label: "Auth failed" };
    case "credential_revoked":
      return { state: "crit", label: "Credential revoked" };
    case "not_checked":
      return { state: "stale", label: "Not checked" };
    case "unrecognized":
      return { state: "neutral", label: "Status not known" };
  }
}
