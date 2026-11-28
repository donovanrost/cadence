import type { LocationQuery } from "vue-router";
import {
  decoders as d,
  requestPage,
  spacecraftRef,
  type ApiResult,
  type Decoded,
  type MissionId,
  type Page,
} from "@/api";
import {
  causeWords,
  ephemerisCauses,
  failedReasons,
  notReadyReasons,
  type EphemerisCause,
} from "./ephemerisReasons.ts";

/**
 * `GET /missions/:m/providers/:p/ephemeris/spacecraft?cause=&reason=` (#972; setup.md): the
 * spacecraft of one provider_ephemeris group, paged by spacecraft id. Now's row deep-links here.
 */
export type MembersKey = Readonly<{
  missionId: MissionId;
  providerId: string;
  cause: EphemerisCause;
  /** One closed code, or null for every member of the cause (each row then has its own). */
  reason: string | null;
}>;

const memberReader = d.object({
  /** name and scid are null for a spacecraft Cadence no longer knows. */
  spacecraft: spacecraftRef,
  reason: d.nullable(d.knownText([...failedReasons, ...notReadyReasons] as const)),
  // free-text: the server's fixed sentence for the code, never a provider's own words.
  detail: d.nullable(d.string),
  attempts: d.integer,
  next_retry_at: d.nullable(d.timestamp),
  since: d.timestamp,
});
export type EphemerisMember = Decoded<typeof memberReader>;

export async function fetchMembersPage(
  key: MembersKey,
  cursor: string | null,
  signal: AbortSignal,
): Promise<ApiResult<Page<EphemerisMember, undefined>>> {
  const params = new URLSearchParams({ cause: key.cause, limit: "50" });
  if (key.reason !== null) params.set("reason", key.reason);
  if (cursor !== null) params.set("cursor", cursor);
  const path = `/missions/${encodeURIComponent(key.missionId)}/providers/${encodeURIComponent(key.providerId)}/ephemeris/spacecraft?${params.toString()}`;
  const r = await requestPage(path, d.array(memberReader, 200), { signal });
  if (!r.ok) return r;
  return { ok: true, value: { items: r.value.value, next: r.value.nextCursor, meta: undefined } };
}

const text = (v: LocationQuery[string] | undefined): string | null => {
  const one = Array.isArray(v) ? v[0] : v;
  return typeof one === "string" && one !== "" ? one : null;
};

/** The route query's cause and reason (Now's deep link); an unknown cause opens no list. */
export function membersQuery(
  query: LocationQuery,
): { cause: EphemerisCause; reason: string | null } | null {
  const cause = ephemerisCauses.find((c) => c === text(query.cause));
  if (!cause) return null;
  return { cause, reason: cause === "norad_id_missing" ? null : text(query.reason) };
}

/** The list's heading: `Spacecraft without a NORAD id`. */
export const membersHeading = (cause: EphemerisCause) => `Spacecraft ${causeWords[cause]}`;

/** The retry column: an upload is retried, a route re-checked. */
export const retryLabel = (cause: EphemerisCause) =>
  cause === "failed" ? "Next retry" : "Next check";
