import { decode, isKnown } from "@/api/index.ts";
import { formatClock } from "@/ui";
import { releaseClause, releaseCode } from "../groups/release.ts";
import { shownValue } from "../groups/resolved.ts";
import type { Attempt, HistoryVerifier } from "./history.ts";

/** ux U70: times with seconds, `03:11:58Z`. */
export const at = (iso: string) => `${formatClock(new Date(iso))}Z`;
/** ' at 03:12:04Z', or nothing when the server gave no time. */
const atOr = (iso: string | null) => (iso ? ` at ${at(iso)}` : "");

/**
 * Why a release failed, from api's failure {kind, code}: a refusal reuses the release-stop words;
 * the free-text failure_reason is never worded (Technical details only).
 */
function refusedWords(a: Attempt, spacecraft: string | null): string {
  const code = a.failure?.code ? decode(releaseCode, a.failure.code) : null;
  return code?.ok
    ? releaseClause(code.value, null, { at: new Date(a.attempted_at), spacecraft })
    : "the server didn't say why";
}

/** ux U70: an uncertain release; a timeout says so, any other cause the general line. */
function uncertainWords(a: Attempt): string {
  // compared-as-text: uncertain codes are the cause's leading atom; only timeout has its own words.
  return a.failure?.code === "timeout"
    ? "the send didn't answer in time, so Cadence can't tell whether it went"
    : "Cadence couldn't confirm whether it was sent";
}

/** ux U70 (U29): 'Resolved as not sent by Mira K. at 03:20:05Z.' or who wasn't recorded. */
function resolvedLine(a: Attempt): string {
  const f = a.failure;
  // compared-as-text: resolved codes are api's two words, not_sent and rejected.
  const as = f?.code === "rejected" ? "rejected" : "not sent";
  const when = f?.at ? ` at ${at(f.at)}` : "";
  const by = f?.by;
  // ux U70: a person or a service identity (an API credential) by its name. A resolution is never
  // Cadence's own act (api: an automatic timeout records 'unknown', not a resolution).
  const who = by?.name ?? null;
  if (who) return `Resolved as ${as} by ${who}${when}`;
  return by
    ? `Resolved as ${as}${when}; who resolved it isn't known`
    : `Resolved as ${as}${when}; who resolved it wasn't recorded`;
}

/**
 * One attempt (ux U70): 'Released at 03:11:58Z during EARENDIL-007 · PUQ 07:20Z pass · 12 bytes',
 * 'Release failed at 03:02:10Z: …', 'Outcome unclear at 03:05:12Z: Cadence couldn't confirm
 * whether it was sent.'; an unknown state shows its own word.
 */
export function attemptLine(a: Attempt, spacecraft: string | null): string {
  const s = a.state;
  if (!isKnown(s)) return `${s.unrecognized.replaceAll("_", " ")} at ${at(a.attempted_at)}`;
  if (s === "released") {
    const during = a.contact ? ` during ${a.contact.label}` : "";
    const size = a.encoded_size_bytes === null ? "" : ` · ${a.encoded_size_bytes} bytes`;
    return `Released at ${at(a.released_at ?? a.attempted_at)}${during}${size}`;
  }
  if (a.failure?.kind === "resolved") return resolvedLine(a);
  if (s === "release_failed")
    return `Release failed at ${at(a.attempted_at)}: ${refusedWords(a, spacecraft)}`;
  if (s === "release_uncertain")
    return `Outcome unclear at ${at(a.attempted_at)}: ${uncertainWords(a)}`;
  if (s === "canceled") return `Canceled at ${at(a.attempted_at)}`;
  const during = a.contact ? ` for ${a.contact.label}` : "";
  return `Waiting to release since ${at(a.attempted_at)}${during}`;
}

/**
 * One verifier (ux U70): 'Mode applied · verified at 03:12:04Z' / '· failed at …: the reading
 * matched its failure condition' / '· timed out at …: no matching telemetry' / '· verify by …'.
 */
export function verifierLine(v: HistoryVerifier): string {
  const name = v.name ?? "Verifier";
  const s = v.state;
  if (!isKnown(s)) return `${name} · ${s.unrecognized.replaceAll("_", " ")}`;
  if (s === "satisfied") return `${name} · verified${atOr(v.matched_at)}`;
  if (s === "failed")
    return `${name} · failed${atOr(v.matched_at)}: the reading matched its failure condition`;
  if (s === "timed_out")
    return `${name} · timed out${atOr(v.timeout_at)}: no matching ${v.evidence?.kind === "transport" ? "transport record" : "telemetry"}`;
  if (s === "canceled") return `${name} · canceled`;
  return v.timeout_at ? `${name} · verify by ${at(v.timeout_at)}` : `${name} · waiting`;
}

/**
 * The matched record on one text-3 line (ux U70): 'HK.sc_mode = 2, received 03:12:03Z', raw only
 * when it differs, quality only when not good; transport '<action> · <phase> at 03:11:58Z'; a gone
 * record 'The matching record is no longer available.' Null when there's nothing to say.
 */
export function evidenceLine(
  v: HistoryVerifier,
): Readonly<{ text: string; caution: string | null; crit?: boolean }> | null {
  if (v.evidence_status === "unavailable")
    return { text: "The matching record is no longer available.", caution: null };
  const e = v.evidence;
  if (!e) return null;
  if (e.kind === "transport") {
    const phase = e.signal_phase === null ? "" : ` ${phaseWord(e.signal_phase)}`;
    return {
      text: `${actionWord(e.action)}${phase} at ${at(e.at)}`,
      caution: null,
      crit: e.signal_phase === "failure",
    };
  }
  const eng = e.engineering_value_json === null ? null : shownValue(e.engineering_value_json);
  const raw = e.raw_value_json === null ? null : shownValue(e.raw_value_json);
  const unit = e.unit && eng !== null ? ` ${e.unit}` : "";
  const value = eng === null ? (raw ?? "no value") : `${eng}${unit}`;
  const rawPart = raw !== null && eng !== null && raw !== eng ? ` (raw ${raw})` : "";
  const quality = e.quality;
  const caution =
    quality === "good" ? null : `quality: ${isKnown(quality) ? quality : quality.unrecognized}`;
  return { text: `${e.point_id} = ${value}${rawPart}, received ${at(e.received_at)}`, caution };
}

type Phase = NonNullable<
  Extract<HistoryVerifier["evidence"], { kind: "transport" }>["signal_phase"]
>;
const PHASES = {
  acceptance: "accepted",
  start: "started",
  completion: "completed",
  failure: "failed",
  custom: "reported",
} as const;
/** ux U70: accepted / started / completed / failed / reported; an unknown phase as its word. */
const phaseWord = (p: Phase) => (isKnown(p) ? PHASES[p] : p.unrecognized.replaceAll("_", " "));

// keyed-by-text: the transport's action/event kinds are free text; unknown ones read as words.
const ACTIONS: Readonly<Record<string, string>> = {
  uplink_request: "Uplink request",
  provider_request: "Provider request",
  transport_event_handled: "Transport event",
  control_input_handled: "Control input",
  timer_handled: "Timer",
};
const actionWord = (a: string) => ACTIONS[a] ?? a.replaceAll("_", " ");

/** Technical details lines: ids, phase, severity, generated/recorded times. */
export function technicalLines(
  attempts: readonly Attempt[],
  verifiers: readonly HistoryVerifier[],
): string[] {
  const lines = attempts.map(
    (a) =>
      `Attempt ${a.attempt_id}${a.path_id ? ` · path ${a.path_id}` : ""}${a.transport_binding_id ? ` · binding ${a.transport_binding_id}` : ""}${a.failure_reason ? ` · ${a.failure_reason}` : ""}`,
  );
  for (const v of verifiers) {
    const phase = isKnown(v.phase) ? v.phase : v.phase.unrecognized;
    const sev =
      v.severity === null
        ? ""
        : ` · severity ${isKnown(v.severity) ? v.severity : v.severity.unrecognized}`;
    const e = v.evidence;
    const rec =
      e === null
        ? ""
        : e.kind === "telemetry"
          ? ` · sample ${e.sample_id}${e.packet_id ? ` · packet ${e.packet_id}` : ""}${e.evidence_id ? ` · evidence ${e.evidence_id}` : ""}${e.generated_at ? ` · generated ${at(e.generated_at)}` : ""}`
          : ` · record ${e.record_id}${e.recorded_at ? ` · recorded ${at(e.recorded_at)}` : ""}`;
    lines.push(`Verifier ${v.verifier_id} (${phase})${sev}${rec}`);
  }
  return lines;
}
