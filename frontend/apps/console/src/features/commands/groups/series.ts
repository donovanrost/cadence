import { windowEnd } from "./verifyTimes.ts";
import type { MissionId } from "@/api/index.ts";
import {
  decoders as d,
  request,
  type ApiResult,
  type Decoded,
  pointId as pointIdReader,
} from "@/api/index.ts";
import type { ComparisonSeries, TimeWindow } from "@/ui";

/**
 * M26 verifier series for Uplink U2 (commanding.md §M26): the plotted command's verifier point,
 * one faint line per target (its own samples only, #38), the commanded value dashed and the band
 * dotted. Numeric points plot; others, and transport-only verifiers, say why not.
 */
export const seriesReader = d.object({
  verifier: d.nullable(
    d.object({ position: d.integer, command_id: d.token, command_name: d.nullable(d.string) }),
  ),
  point: d.nullable(
    // Live sends type null for a point the catalog doesn't type (commanding.md says numeric | enum
    // | text): read it, and plot only if the samples are numbers.
    d.object({
      id: d.token,
      name: d.string,
      unit: d.nullable(d.string),
      type: d.nullable(d.known(["numeric", "enum", "text"] as const)),
    }),
  ),
  reason: d.optional(
    d.nullable(d.known(["verified_by_uplink_acknowledgement", "no_verifier"] as const)),
  ),
  commanded: d.nullable(d.object({ value_json: d.string, comparison: d.nullable(d.string) })),
  band: d.nullable(d.object({ min_json: d.nullable(d.string), max_json: d.nullable(d.string) })),
  window: d.nullable(d.object({ from: d.timestamp, to: d.timestamp })),
  targets: d.array(
    d.object({
      spacecraft_id: d.token,
      name: d.nullable(d.string),
      verifier_state: d.nullable(d.known(["pending", "satisfied", "failed", "timed_out"] as const)),
      /** U68 R4 (api 45563ffe8): that target's verifier instance; null exactly when the state is. */
      verifier: d.optional(
        d.nullable(
          d.object({
            instance_id: d.token,
            verifier_id: d.token,
            severity: d.nullable(d.knownText(["info", "warning", "error", "critical"] as const)),
            failure_code: d.nullable(
              d.knownText(["timed_out", "failure_criteria_matched"] as const),
            ),
          }),
        ),
      ),
      /** U69 A4a (api, on u68-r3): the instance's deadline and match time; optional until shipped. */
      timeout_at: d.optional(d.nullable(d.timestamp)),
      matched_at: d.optional(d.nullable(d.timestamp)),
      samples: d.array(d.object({ t: d.timestamp, value_json: d.nullable(d.string) }), 1_000),
    }),
    100,
  ),
  target_count: d.integer,
  truncated: d.boolean,
  summary: d.object({ met: d.integer, not_met: d.integer, pending: d.integer }),
  /** commanding.md: degraded = the history store didn't answer in 3 s, so samples are empty. */
  telemetry: d.optional(d.known(["ok", "degraded"] as const)),
  /**
   * U51 (api): every telemetry verifier point in the group, with the targets whose own verifiers
   * watch it, by position then verifier order. Plot one with `?point=`; the default is the first.
   */
  points: d.optional(
    d.array(
      d.object({
        point_id: pointIdReader,
        name: d.string,
        // free-text: the verifier's name ("Mode applied")
        verifier_name: d.string,
        position: d.integer,
        spacecraft_ids: d.array(d.token, 10_000),
      }),
      50,
    ),
  ),
});
export type VerifierSeries = Decoded<typeof seriesReader>;
export type VerifierPoint = NonNullable<VerifierSeries["points"]>[number];

export function fetchVerifierSeries(
  missionId: MissionId,
  groupId: string,
  signal?: AbortSignal,
  point?: string,
): Promise<ApiResult<VerifierSeries>> {
  const q = point ? `?point=${encodeURIComponent(point)}` : "";
  return request(
    `/missions/${encodeURIComponent(missionId)}/command-groups/${encodeURIComponent(groupId)}/verifier-series${q}`,
    seriesReader,
    signal ? { signal } : {},
  );
}

const num = (j: string | null | undefined) => {
  const v = j === null || j === undefined ? NaN : Number(j);
  return Number.isFinite(v) ? v : null;
};

/** The point's name; live falls back to its id when the catalog has none, which reads as noise. */
export function pointName(s: VerifierSeries | null): string {
  const p = s?.point;
  return p && p.name !== p.id ? p.name : "the verifier point";
}

const hasNumbers = (s: VerifierSeries) =>
  s.targets.some((t) => t.samples.some((p) => num(p.value_json) !== null));

/** Why there's no plot, in words; null when there is one. */
export function notPlottable(s: VerifierSeries): string | null {
  if (!s.point)
    return s.reason === "no_verifier"
      ? "Not plottable: this command has no verifier"
      : "Not plottable: verified by uplink acknowledgement only";
  if (s.point.type !== null && s.point.type !== "numeric")
    return `Not plottable: ${pointName(s)} isn't numeric`;
  if (!s.window) return "Nothing to plot until the first uplink is released";
  if (!hasNumbers(s)) return `No readings of ${pointName(s)} in the verify window`;
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
    s.summary.pending ? `${s.summary.pending} pending${windowEnd(s)}` : null,
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
    // ux U25 (#237): never the id for a name.
    name: t.name ?? "Unknown spacecraft",
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

/** U51: plot one panel per point when the group's targets watch more than one. */
export const perPoint = (s: VerifierSeries | null) => (s?.points?.length ?? 0) > 1;

/** A point plot's caption: `Mode applied · EARENDIL-001`, or `… · 499 targets` above 3. */
export function pointCaption(p: VerifierPoint, nameOf: (spacecraftId: string) => string): string {
  const n = p.spacecraft_ids.length;
  const who = n <= 3 ? p.spacecraft_ids.map(nameOf).join(", ") : `${n} targets`;
  return [p.verifier_name, who].filter(Boolean).join(" · ");
}

/**
 * The plot's sentence (a11y checklist C, Uplink & verify): the point, the targets it names (up to 3,
 * then "and N more"), and how they came out, zero counts left out. "EPS.VBAT for EARENDIL-001,
 * EARENDIL-002 and 3 more: 4 met, 1 not met."
 */
export function plotSentence(s: VerifierSeries): string {
  const names = s.targets.map((t) => t.name ?? "Unknown spacecraft");
  const shown = names.slice(0, 3);
  const more = s.target_count - shown.length;
  const who =
    shown.length === 0
      ? "no targets"
      : more > 0
        ? `${shown.join(", ")} and ${more} more`
        : shown.length > 1
          ? `${shown.slice(0, -1).join(", ")} and ${shown.at(-1) ?? ""}`
          : (shown[0] ?? "");
  const outcome = [
    s.summary.met ? `${s.summary.met} met` : null,
    s.summary.not_met ? `${s.summary.not_met} not met` : null,
    s.summary.pending ? `${s.summary.pending} pending${windowEnd(s)}` : null,
  ].filter((p): p is string => p !== null);
  return `${pointName(s)} for ${who}${outcome.length ? `: ${outcome.join(", ")}` : ""}.`;
}
