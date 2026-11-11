import { decoders as d, request, type ApiResult, type Decoded } from "@/api/index.ts";
import type { ComparisonSeries, TimeWindow } from "@/ui";

/**
 * M26 verifier series for Uplink U2 (commanding.md §M26): the plotted command's verifier point,
 * one faint line per target (its own samples only, #38), the commanded value dashed and the band
 * dotted. Numeric points plot; others, and transport-only verifiers, say why not.
 */
const seriesReader = d.object({
  verifier: d.nullable(
    d.object({ position: d.integer, command_id: d.token, command_name: d.nullable(d.string) }),
  ),
  point: d.nullable(
    d.object({ id: d.token, name: d.string, unit: d.nullable(d.string), type: d.token }),
  ),
  reason: d.optional(d.nullable(d.token)),
  commanded: d.nullable(d.object({ value_json: d.string, comparison: d.nullable(d.string) })),
  band: d.nullable(d.object({ min_json: d.nullable(d.string), max_json: d.nullable(d.string) })),
  window: d.nullable(d.object({ from: d.timestamp, to: d.timestamp })),
  targets: d.array(
    d.object({
      spacecraft_id: d.token,
      name: d.nullable(d.string),
      verifier_state: d.nullable(d.token),
      samples: d.array(d.object({ t: d.timestamp, value_json: d.nullable(d.string) }), 1_000),
    }),
    100,
  ),
  target_count: d.integer,
  truncated: d.boolean,
  summary: d.object({ met: d.integer, not_met: d.integer, pending: d.integer }),
  telemetry: d.optional(d.token),
});
export type VerifierSeries = Decoded<typeof seriesReader>;

export function fetchVerifierSeries(
  missionId: string,
  groupId: string,
  signal?: AbortSignal,
): Promise<ApiResult<VerifierSeries>> {
  return request(
    `/missions/${encodeURIComponent(missionId)}/command-groups/${encodeURIComponent(groupId)}/verifier-series`,
    seriesReader,
    signal ? { signal } : {},
  );
}

const num = (j: string | null | undefined) => {
  const v = j === null || j === undefined ? NaN : Number(j);
  return Number.isFinite(v) ? v : null;
};

/** Why there's no plot, in words; null when there is one. */
export function notPlottable(s: VerifierSeries): string | null {
  if (!s.point)
    return s.reason === "no_verifier"
      ? "Not plottable: this command has no verifier"
      : "Not plottable: verified by uplink acknowledgement only";
  if (s.point.type !== "numeric") return `Not plottable: ${s.point.name} isn't numeric`;
  if (!s.window) return "Nothing to plot until the first uplink is released";
  return null;
}

/** "02 SET_TEMP · 34 met 8.0 · 1 did not · 3 pending" (CommandFlow U2 header meta). */
export function seriesMeta(s: VerifierSeries): string {
  const v = s.verifier;
  const head = v
    ? `${String(v.position + 1).padStart(2, "0")} ${v.command_name ?? v.command_id}`
    : null;
  const target = s.commanded ? ` ${s.commanded.value_json}` : "";
  const parts = [
    head,
    `${s.summary.met} met${target}`,
    s.summary.not_met ? `${s.summary.not_met} did not` : null,
    s.summary.pending ? `${s.summary.pending} pending` : null,
  ].filter((p): p is string => p !== null);
  return parts.join(" · ");
}

/** Chart input: targets as faint lines (failed ones brighter), commanded dashed, band dotted. */
export function seriesChart(s: VerifierSeries): {
  window: TimeWindow;
  lines: ComparisonSeries[];
} | null {
  if (notPlottable(s) || !s.window) return null;
  const window = { from: Date.parse(s.window.from), to: Date.parse(s.window.to) };
  const flat = (v: number | null): ComparisonSeries[] =>
    v === null
      ? []
      : [
          {
            points: [
              { t: window.from, min: v, mean: v, max: v },
              { t: window.to, min: v, mean: v, max: v },
            ],
            tone: "readout",
            dash: "dashed",
            name: "Commanded",
          },
        ];
  const lines: ComparisonSeries[] = s.targets.map((t) => ({
    name: t.name ?? t.spacecraft_id,
    points: t.samples.flatMap((p) => {
      const v = num(p.value_json);
      return v === null ? [] : [{ t: Date.parse(p.t), min: v, mean: v, max: v }];
    }),
    tone: t.verifier_state === "failed" || t.verifier_state === "timed_out" ? "text-2" : "text-4",
    dash: "solid",
  }));
  const band = [num(s.band?.min_json), num(s.band?.max_json)].flatMap((v) =>
    flat(v).map((l) => ({ ...l, tone: "text-3" as const, dash: "dotted" as const, name: "Band" })),
  );
  return { window, lines: [...lines, ...flat(num(s.commanded?.value_json)), ...band] };
}
