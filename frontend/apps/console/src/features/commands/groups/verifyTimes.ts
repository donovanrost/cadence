import { formatClock, formatHourMinute } from "@/ui";
import type { VerifierSeries } from "./series.ts";

/** ux U69 A4a: verify times per target, with seconds. */
type SeriesTarget = VerifierSeries["targets"][number];
const at = (iso: string) => `${formatClock(new Date(iso))}Z`;

/**
 * 'Verify by 03:12:30Z' / 'Verified at 03:11:58Z' / 'Timed out at 03:12:30Z: no matching
 * telemetry' / 'Failed at …'; null when the server gave no time.
 */
export function verifyTime(t: SeriesTarget | undefined): string | null {
  if (!t) return null;
  if (t.verifier_state === "pending" && t.timeout_at) return `Verify by ${at(t.timeout_at)}`;
  if (t.verifier_state === "satisfied" && t.matched_at) return `Verified at ${at(t.matched_at)}`;
  if (t.verifier_state === "timed_out" && t.timeout_at)
    return `Timed out at ${at(t.timeout_at)}: no matching telemetry`;
  if (t.verifier_state === "failed" && t.matched_at) return `Failed at ${at(t.matched_at)}`;
  return null;
}

/** A target's verify time from the series, when the series covers it. */
export const verifyTimeOf = (s: VerifierSeries | null, spacecraftId: string) =>
  verifyTime(s?.targets.find((t) => t.spacecraft_id === spacecraftId));

/**
 * The pending count's end (ux U69 A4a): ' · window closes 03:12:30Z', or ' · windows close 03:12Z–03:20Z'
 * when the pending targets' deadlines differ; nothing without deadlines.
 */
export function windowEnd(s: Pick<VerifierSeries, "targets">): string {
  const ends = s.targets
    .filter((t) => t.verifier_state === "pending" && t.timeout_at)
    .map((t) => Date.parse(t.timeout_at ?? ""))
    .sort((a, b) => a - b);
  const first = ends[0];
  const last = ends.at(-1);
  if (first === undefined || last === undefined) return "";
  if (first === last) return ` · window closes ${at(new Date(first).toISOString())}`;
  // ux: 'windows close 03:12–03:20Z', one Z at the end.
  const from = formatHourMinute(new Date(first)).replace(/Z$/, "");
  return ` · windows close ${from}–${formatHourMinute(new Date(last))}`;
}
