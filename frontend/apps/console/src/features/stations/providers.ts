import type { MissionId } from "@/api/index.ts";
import { decoders as d, isError, request, type ApiError, type Decoded } from "@/api";
import { failureOutcome } from "@/features/changes/index.ts";
import { formatShort, type OpState } from "@/ui";
import { providerReader, type MissionProvider } from "./api.ts";

/**
 * L12 mission providers (api-ops 4f81a1d0d, setup.md): add by binding an org
 * account grant, validate, sync stations, archive. Validate and sync answer a result, not an error.
 */
const base = (missionId: MissionId) => `/missions/${encodeURIComponent(missionId)}/providers`;

export const policyModes = ["approval_required", "bounded_automatic"] as const;
const option = d.object({ key: d.token, label: d.string });
const optionsReader = d.object({
  grants: d.array(
    d.object({
      id: d.token,
      version: d.integer,
      account: d.object({ id: d.token, name: d.string, provider: option }),
      allowed_stations: d.nullable(d.array(d.string, 500)),
      allowed_services: d.nullable(d.array(d.string, 500)),
    }),
    200,
  ),
  policy_modes: d.array(d.object({ key: d.known(policyModes), label: d.string }), 10),
  deadline_behaviors: d.array(option, 10),
});
export type ProviderOptions = Decoded<typeof optionsReader>;
export function fetchProviderOptions(missionId: MissionId, signal: AbortSignal) {
  return request(`${base(missionId)}/options`, optionsReader, { signal });
}

export type BoundedBody = Readonly<{
  approved_station_substitutions: readonly string[];
  minimum_retained_duration_seconds: number;
}>;
export type AddProviderBody = Readonly<{
  grant_id: string;
  display_name: string;
  policy_mode: (typeof policyModes)[number];
  deadline_behavior?: string;
  bounded?: BoundedBody;
  /** The grant's version as offered; a stale one is 409 grant_changed. */
  expected_grant_version?: number;
}>;
const one = d.object({ provider: providerReader });
export async function addProvider(missionId: MissionId, body: AddProviderBody) {
  const r = await request(base(missionId), one, { method: "POST", body });
  return r.ok ? { ok: true as const, value: r.value.provider } : r;
}

const result = d.object({
  ok: d.boolean,
  stations: d.optional(d.nullable(d.integer)),
  // free-text: the provider's own message, shown as is.
  message: d.nullable(d.string),
});
const checked = d.object({ provider: providerReader, result });
export type ProviderCheck = Decoded<typeof checked>;
/** Validate (contact the provider) or sync (pull its stations). Inline: can take seconds. */
export function checkProvider(missionId: MissionId, id: string, what: "validate" | "sync") {
  return request(`${base(missionId)}/${encodeURIComponent(id)}/${what}`, checked, {
    method: "POST",
    body: {},
  });
}
export async function archiveProvider(missionId: MissionId, id: string, reason: string) {
  const r = await request(`${base(missionId)}/${encodeURIComponent(id)}/archive`, one, {
    method: "POST",
    body: { reason },
  });
  return r.ok ? { ok: true as const, value: r.value.provider } : r;
}

/** "Validated: the provider answered." / "Sync failed: <provider's message>". */
export function checkSentence(what: "validate" | "sync", c: ProviderCheck): string {
  const r = c.result;
  // api-ops' messages are sentences ("The provider didn't answer in time."): one period, not two.
  const why = `${(r.message ?? "no reason given").replace(/\.$/, "")}.`;
  if (what === "validate")
    return r.ok ? "Validated: the provider answered." : `Validation failed: ${why}`;
  if (!r.ok) return `Sync failed: ${why}`;
  return typeof r.stations === "number" ? `Synced ${r.stations} stations.` : "Synced.";
}

/** One health line: "Healthy · 11-13 02:10Z" / "Failed · <error>" / "Never checked". */
export function healthLine(c: MissionProvider["health"]["validate"]) {
  const state: OpState =
    c.status === "healthy" ? "nominal" : c.status === "failed" ? "crit" : "off";
  if (c.status === null) return { state, text: "Never checked" };
  const at = c.checked_at ? ` · ${formatShort(new Date(c.checked_at))}` : "";
  if (c.status === "failed") return { state, text: `Failed${at}${c.error ? ` · ${c.error}` : ""}` };
  return { state, text: c.status === "healthy" ? `Healthy${at}` : `Unknown${at}` };
}

/** One sentence for a refused write (U20). */
export function providerFailure(error: ApiError): string {
  if (isError(error, "grant_revoked"))
    return "That account grant was revoked. Ask an org admin to grant the account again.";
  if (isError(error, "grant_changed"))
    return "That grant changed since you loaded it. Reload and choose again.";
  return failureOutcome(error, "changed").sentence;
}

/** The Add provider sheet's draft (bounded fields as typed). */
export type AddDraft = Readonly<{
  grant: string;
  name: string;
  mode: "" | (typeof policyModes)[number];
  substitutions: string;
  retainedMinutes: string;
}>;
export const blankAdd: AddDraft = {
  grant: "",
  name: "",
  mode: "",
  substitutions: "",
  retainedMinutes: "",
};

/** The POST body, or why it can't go yet. */
export function addBody(
  a: AddDraft,
): { ok: true; body: AddProviderBody } | { ok: false; why: string } {
  if (!a.grant) return { ok: false, why: "Choose an account grant." };
  if (!a.name.trim()) return { ok: false, why: "Name the provider." };
  if (a.mode === "") return { ok: false, why: "Choose how bookings are approved." };
  if (a.mode === "approval_required")
    return {
      ok: true,
      body: { grant_id: a.grant, display_name: a.name.trim(), policy_mode: a.mode },
    };
  const minutes = /^\d+$/.test(a.retainedMinutes.trim()) ? Number(a.retainedMinutes.trim()) : 0;
  if (minutes < 1) return { ok: false, why: "Say the shortest pass worth keeping, in minutes." };
  return {
    ok: true,
    body: {
      grant_id: a.grant,
      display_name: a.name.trim(),
      policy_mode: a.mode,
      bounded: {
        approved_station_substitutions: a.substitutions
          .split(",")
          .map((s) => s.trim())
          .filter(Boolean),
        minimum_retained_duration_seconds: minutes * 60,
      },
    },
  };
}

type GrantState = NonNullable<MissionProvider["grant"]>["state"];
/** ux SettingsAuditProviders.md: the grant's state in words; an unknown state shows only its version. */
const grantWords: Readonly<Record<GrantState, string | null>> = {
  active: "Active",
  revoked: "Revoked",
  unrecognized: null,
};

/** The Account grant value: "Active · v3", "Revoked · v3" (crit), "v3", or no grant at all. */
export function grantLine(grant: MissionProvider["grant"]): { text: string; revoked: boolean } {
  if (!grant) return { text: "None: set up before account grants", revoked: false };
  const word = grantWords[grant.state];
  return {
    text: word ? `${word} · v${grant.version}` : `v${grant.version}`,
    revoked: grant.state === "revoked",
  };
}

/** The detail's crit callout for a revoked grant; members don't see the account's name. */
export function revokedSentence(accountName: string | null): string {
  const whose = accountName ? `grant to ${accountName}` : "grant";
  return `The organization revoked this mission's ${whose}, so this provider can't be used until it's added again from an active grant.`;
}
