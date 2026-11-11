import {
  decoders as d,
  DecodeError,
  request,
  type ApiResult,
  type Decoded,
  type Reader,
} from "@/api/index.ts";
import { outcomes, owners } from "@/features/review/api.ts";

/**
 * Investigate › Passes (Investigate.md §Passes; ops.md §spacecraft/:id/passes, api 324428aa):
 * P1 coverage and P3's queued counts. P2/P3 rows come from /passes and P4 from pass-review rows.
 */
const station = d.nullable(
  d.object({ id: d.nullable(d.token), code: d.nullable(d.string), name: d.nullable(d.string) }),
);
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
      state: d.token,
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
  missionId: string,
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
  station: d.nullable(d.object({ code: d.nullable(d.string), name: d.nullable(d.string) })),
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
  missionId: string,
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
