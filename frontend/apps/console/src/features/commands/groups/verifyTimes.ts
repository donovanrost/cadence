import { formatClock, formatHourMinute } from "@/ui";
import type { VerifierSeries } from "./series.ts";
import type { GroupMember, GroupTarget } from "./show.ts";

/** ux U69 A4a: verify times per target, with seconds. */
const at = (iso: string) => `${formatClock(new Date(iso))}Z`;

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

/**
 * ux U69 A4a from the member (api 3438b783c), so transport-only verifiers have their time too:
 * 'Verify by …' while it's being verified, then 'Verified at …', 'Timed out at …: no matching
 * telemetry' or 'Failed at …'; null otherwise.
 */
export function memberVerifyTime(m: GroupMember | undefined): string | null {
  if (!m) return null;
  if (m.verified_at) return `Verified at ${at(m.verified_at)}`;
  if (m.timed_out_at) return `Timed out at ${at(m.timed_out_at)}: no matching telemetry`;
  if (m.failed_at) return `Failed at ${at(m.failed_at)}`;
  if (m.stage === "executed" && m.verify_by) return `Verify by ${at(m.verify_by)}`;
  return null;
}

/** A target's verify time: the member at the target's own stage (the one its tag names). */
export const targetVerifyTime = (t: GroupTarget | undefined) =>
  memberVerifyTime(t?.members.find((m) => m.stage === t.stage));
