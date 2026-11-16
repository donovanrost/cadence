import { isKnown } from "@/api/index.ts";
import { formatHourMinute, plural, type OpState } from "@/ui";
import { formatValue } from "@/features/alarms/index.ts";
import { pointName, type VerifierSeries } from "./series.ts";
import { targetVerifyTime } from "./verifyTimes.ts";
import type { Group, GroupMember, GroupTarget } from "./show.ts";
import { memberStageWord, NEEDS_YOU, STAGE_STATE } from "./words.ts";

/**
 * N · Needs you cards (CommandFlow C3): one per target a human has to look at, with a plain
 * sentence of what happened. Verify failures read the M26 series (what the point last read against
 * what was commanded); release failures and no-ACK say what's known; a target held behind an
 * uncertain release (commanding.md `blocked`) waits on recovery, so it gets no Re-send. No
 * automatic retry (DECISIONS #69): Re-send goes back through Compose and the normal GO.
 */
export type NeedsYouCard = Readonly<{
  target: GroupTarget;
  state: OpState;
  tag: string;
  explanation: string;
  /** The uplink ended (failed or unclear), so a fresh request can replace it. */
  resend: boolean;
}>;

/** A JSON value as a reading: `8`, `SAFE`. */
function shown(json: string): string {
  try {
    const v: unknown = JSON.parse(json);
    if (typeof v === "number" || typeof v === "string" || typeof v === "boolean")
      return formatValue(v) ?? json;
  } catch {
    // not JSON: show it as sent
  }
  return json;
}

/** The target's last reading of the series point, when the series covers this member. */
function lastReading(series: VerifierSeries | null, t: GroupTarget, m: GroupMember | undefined) {
  if (!series?.point || !m || series.verifier?.position !== m.position) return undefined;
  const samples = series.targets.find((x) => x.spacecraft_id === t.spacecraft_id)?.samples ?? [];
  const last = [...samples].reverse().find((p) => p.value_json !== null);
  return last?.value_json ? { value: shown(last.value_json), at: last.t } : null;
}

function verifyLine(
  group: Group,
  series: VerifierSeries | null,
  t: GroupTarget,
  m: GroupMember | undefined,
  cmd: string,
): string {
  const failure = [...group.events]
    .reverse()
    .find(
      (e) =>
        e.kind === "member_failed" &&
        e.payload?.spacecraft_id === t.spacecraft_id &&
        e.payload.position === m?.position,
    );
  const timedOut = failure?.payload?.reason === "verify_timed_out";
  const reading = lastReading(series, t, m);
  if (reading === undefined)
    return `${cmd} was sent, but verification ${timedOut ? "timed out" : "failed"}.`;
  const point = pointName(series);
  if (reading === null)
    return `${cmd} was sent, but no reading of ${point} arrived before verification ${timedOut ? "timed out" : "ended"}.`;
  const unit = series?.point?.unit ? ` ${series.point.unit}` : "";
  const want = series?.commanded
    ? `; it was commanded to ${shown(series.commanded.value_json)}${unit}`
    : "";
  return `${cmd} was sent, but ${point} last read ${reading.value}${unit} at ${formatHourMinute(new Date(reading.at))}${want}.`;
}

function stoppedLine(t: GroupTarget): string {
  const n = t.members.filter(
    (m) => m.stage === "canceled" && m.end_reason === "earlier_command_failed",
  ).length;
  return n ? ` ${plural(n, "later uplink")} to it ${n === 1 ? "was" : "were"} stopped.` : "";
}

function card(group: Group, series: VerifierSeries | null, t: GroupTarget): NeedsYouCard | null {
  const m = t.members.find((x) => x.stage === t.stage);
  const cmd = m?.command_name ?? "The command";
  const base = {
    target: t,
    state: STAGE_STATE[t.stage],
    tag: memberStageWord(t.stage, group.state),
  };
  if (t.stage === "verify_failed") {
    // ux U69 A4a: when it timed out or failed, with seconds.
    const time = targetVerifyTime(t);
    return {
      ...base,
      explanation:
        verifyLine(group, series, t, m, cmd) + (time ? ` ${time}.` : "") + stoppedLine(t),
      resend: true,
    };
  }
  if (t.stage === "release_failed")
    return {
      ...base,
      explanation: `${cmd} wasn't sent: the uplink release failed.${stoppedLine(t)}`,
      resend: true,
    };
  if (t.stage === "indeterminate")
    return {
      ...base,
      explanation: `No ACK for ${cmd}: Cadence can't tell whether it arrived. Check the spacecraft before re-sending.`,
      resend: true,
    };
  if (!t.blocked) return null;
  return {
    ...base,
    state: "caution",
    tag: "Lane held",
    explanation:
      t.blocked.reason === "lane_release_uncertain"
        ? "Waiting: an earlier release on its uplink has an unknown outcome, so nothing behind it goes until that's resolved."
        : `Waiting: ${(isKnown(t.blocked.reason) ? t.blocked.reason : t.blocked.reason.unrecognized).replaceAll("_", " ")}.`,
    resend: false,
  };
}

export function needsYouCards(group: Group, series: VerifierSeries | null): NeedsYouCard[] {
  return group.targets.flatMap((t) => {
    if (!NEEDS_YOU.includes(t.stage) && !t.blocked) return [];
    const c = card(group, series, t);
    return c ? [c] : [];
  });
}
