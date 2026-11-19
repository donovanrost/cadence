import type { MissionId } from "@/api/index.ts";
import {
  decoders as d,
  DecodeError,
  stationRef,
  request,
  type ApiResult,
  type Decoded,
  type Reader,
} from "@/api/index.ts";
import type { OpState } from "@/ui";
import { outcomes, owners, type Owner } from "@/features/review/api.ts";
import { causeText, outcomeTag, ownerWord } from "@/features/review/format.ts";

/**
 * Investigate › Passes (Investigate.md §Passes; ops.md §spacecraft/:id/passes, api 324428aa):
 * P1 coverage and P3's queued counts. P2/P3 rows come from /passes and P4 from pass-review rows.
 */
/** §12 A5: the shared station reference (api/entities.ts). */
const station = d.nullable(stationRef);
/** `{<pass id>: count}`, only passes with groups queued. */
const queuedCounts: Reader<Readonly<Record<string, number>>> = (value, path = "") => {
  if (typeof value !== "object" || value === null || Array.isArray(value))
    throw new DecodeError(path, "object");
  const out: Record<string, number> = {};
  for (const [k, v] of Object.entries(value)) out[k] = d.integer(v, `${path}.${k}`);
  return out;
};

const coverageReader = d.object({
  observed_at: d.timestamp,
  coverage: d.object({
    last_contact: d.nullable(d.object({ pass_id: d.token, station, los_at: d.timestamp })),
    next_contact: d.nullable(d.object({ pass_id: d.token, station, aos_at: d.timestamp })),
    passes_next_24h: d.integer,
    longest_gap: d.nullable(d.object({ seconds: d.integer, from: d.timestamp, to: d.timestamp })),
    none_within_6h: d.boolean,
    contact_rule: d.object({
      /** Reads.SpacecraftPasses: none (no rule today) | met | short. */
      state: d.known(["none", "met", "short"] as const),
      have: d.integer,
      need: d.integer,
      rules: d.array(
        d.object({
          requirement_id: d.token,
          text: d.nullable(d.string),
          have: d.integer,
          need: d.integer,
          met: d.boolean,
        }),
        50,
      ),
    }),
  }),
  queued: queuedCounts,
});
export type SpacecraftCoverage = Decoded<typeof coverageReader>;

export function fetchCoverage(
  missionId: MissionId,
  spacecraftId: string,
  signal?: AbortSignal,
): Promise<ApiResult<SpacecraftCoverage>> {
  return request(
    `/missions/${encodeURIComponent(missionId)}/spacecraft/${encodeURIComponent(spacecraftId)}/passes`,
    coverageReader,
    signal ? { signal } : {},
  );
}

const recentRow = d.object({
  id: d.token,
  station,
  planned_aos: d.timestamp,
  planned_los: d.timestamp,
  actual_aos: d.nullable(d.timestamp),
  actual_los: d.nullable(d.timestamp),
  received_bytes: d.nullable(d.integer),
  outcome: d.oneOf(outcomes),
  cause: d.nullable(d.string),
  owner: d.nullable(d.oneOf(owners)),
});
export type RecentPass = Decoded<typeof recentRow>;
const recentReader = d.object({ rows: d.array(recentRow, 500) });

/** P4: the last 7 days of this spacecraft's pass results. */
export function fetchRecentPasses(
  missionId: MissionId,
  spacecraftId: string,
  signal?: AbortSignal,
): Promise<ApiResult<Decoded<typeof recentReader>>> {
  const now = Date.now();
  const q = new URLSearchParams({
    spacecraft_id: spacecraftId,
    from: new Date(now - 7 * 86_400_000).toISOString(),
    to: new Date(now).toISOString(),
    limit: "500",
  });
  return request(
    `/missions/${encodeURIComponent(missionId)}/pass-review/rows?${q.toString()}`,
    recentReader,
    signal ? { signal } : {},
  );
}

/** "3 of 3 contacts today · rule met" / "2 of 3 contacts today" / null (no rule). */
export function ruleWords(c: SpacecraftCoverage["coverage"]["contact_rule"]) {
  if (c.state === "none") return null;
  return {
    text: `${c.have} of ${c.need} contacts today${c.state === "met" ? " · rule met" : ""}`,
    caution: c.state !== "met",
  };
}

/** P4 day groups, newest first. */
export function byDay(rows: readonly RecentPass[]): { day: string; rows: RecentPass[] }[] {
  const groups = new Map<string, RecentPass[]>();
  for (const r of [...rows].sort((a, b) => Date.parse(b.planned_aos) - Date.parse(a.planned_aos))) {
    const day = r.planned_aos.slice(0, 10);
    groups.set(day, [...(groups.get(day) ?? []), r]);
  }
  return [...groups.entries()].map(([day, rs]) => ({ day, rows: rs }));
}

/** "1.2 MB" style received bytes; "—" when unknown. */
export function bytesWords(n: number | null): string {
  if (n === null) return "—";
  const units = ["B", "kB", "MB", "GB"];
  let v = n;
  let i = 0;
  while (v >= 1000 && i < units.length - 1) {
    v /= 1000;
    i += 1;
  }
  return `${i === 0 ? v : v.toFixed(1)} ${units[i]}`;
}

/**
 * Two bookings of the same window at the same station (one missed, one re-booked): the later one
 * in the list says "re-booked" (ux review 4).
 */
export function rebooked(rows: readonly RecentPass[], r: RecentPass): boolean {
  const same = rows.filter((x) => sameWindow(x, r));
  return same.length > 1 && same[0]?.id !== r.id;
}

const sameWindow = (a: RecentPass, b: RecentPass) =>
  a.planned_aos === b.planned_aos &&
  a.planned_los === b.planned_los &&
  (a.station?.code ?? a.station?.name) === (b.station?.code ?? b.station?.name);

/**
 * P4 tag (ux #7): a booking that didn't fly while another booking of the same window did was
 * rejected and replaced, not a lost contact: off `Rejected`. Crit `Missed` only when none flew.
 */
export function recentTag(
  rows: readonly RecentPass[],
  r: RecentPass,
): Readonly<{ state: OpState; label: string }> {
  const flownElsewhere =
    r.actual_aos === null &&
    rows.some((x) => x.id !== r.id && x.actual_aos !== null && sameWindow(x, r));
  return flownElsewhere ? { state: "off", label: "Rejected" } : outcomeTag(r.outcome);
}

/** P4 cause (ux #8): the owner in brackets only when the cause doesn't already name it. */
export function causeWithOwner(cause: string | null, owner: Owner | null): string {
  const text = causeText(cause);
  if (!owner) return text;
  const who = ownerWord[owner].toLowerCase();
  return text.toLowerCase().includes(who) ? text : `${text} (${who})`;
}
