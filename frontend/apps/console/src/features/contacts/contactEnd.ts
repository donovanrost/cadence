import type { MissionId } from "@/api/index.ts";
import {
  decoders as d,
  describeApiError,
  detailsOf,
  isError,
  isKnown,
  request,
  type ApiError,
} from "@/api/index.ts";
import { plural } from "@/ui";
import {
  contactEndCauses,
  passReader,
  providerReasonCodes,
  type ContactEnded,
  type Pass,
  type QueuedCommands,
} from "./api.ts";

/**
 * U55: cancel a scheduled contact before AOS, or end one now while live. Both stop Cadence's
 * side only; the provider's booking is unchanged (that's Release). Operators (operate_mission).
 * U56 words Cadence's own cancels (the reservation failed or the provider canceled it).
 */

const hhmm = (iso: string) => `${iso.slice(11, 16)}Z`;
/** §4 short form: "13:04Z" today, "11-13 13:04Z" otherwise. */
const short = (iso: string, now: Date) =>
  `${iso.slice(0, 10) === now.toISOString().slice(0, 10) ? "" : `${iso.slice(5, 10)} `}${hhmm(iso)}`;
const quoted = (reason: string | null) => (reason ? `: “${reason.trim()}”` : "");

/**
 * ux U56: the provider's code is worded or left out, its text is quoted. domain sends them apart
 * (reason_code, reason); an older read without reason_code falls back to treating a bare
 * snake_case reason as a code.
 */
const CODE = /^[a-z0-9_]+$/;
type ProviderReasonCode = (typeof providerReasonCodes)[number];
const CODE_WORDS: Readonly<Record<ProviderReasonCode, string>> = {
  delivery_descriptor_conflicts_with_transport:
    "its delivery settings don't match the transport set up in Cadence",
};
function split(e: ContactEnded): Readonly<{ code: string | null; text: string | null }> {
  const r = e.reason?.trim() || null;
  if (e.reason_code !== undefined) {
    const c = e.reason_code;
    return { code: c === null ? null : isKnown(c) ? c : c.unrecognized, text: r };
  }
  return r && CODE.test(r) ? { code: r, text: null } : { code: null, text: r };
}
/** The raw provider code behind a Cadence cancel, for Technical details. */
export const endedCode = (e: ContactEnded | null | undefined): string | null =>
  e && e.by?.kind === "system" ? split(e).code : null;
function providerReason(e: ContactEnded): string {
  const { code, text } = split(e);
  // A legacy bare reason may be any snake_case text: match it against the codes the console words.
  const known = providerReasonCodes.find((k) => k === code);
  const words = known ? CODE_WORDS[known] : undefined;
  const parts = [words ?? null, text ? `“${text}”` : null].filter((p): p is string => p !== null);
  return parts.length ? ` (${parts.join(": ")})` : "";
}

/** Every cause but the operator's own cancel is Cadence's. */
const CADENCE_CANCELS: Readonly<
  Record<Exclude<(typeof contactEndCauses)[number], "operator">, (p: string) => string>
> = {
  provider_failed: (p) => `${p} couldn't book this pass`,
  provider_canceled: (p) => `${p} canceled this pass`,
  provider_rejected: (p) => `${p} rejected the booking for this pass`,
};

/** History line: "Canceled by Mira K. at 12:58Z: “Its booking failed.”" (and U56's Cadence forms). */
export function endedLine(e: ContactEnded, provider: string | null, now: Date): string {
  const what0 = e.kind === "ended_early" ? "Ended early" : "Canceled";
  // ux U55: a legacy cancel without an action record says what's missing (U20), so it isn't
  // read as Cadence's or the provider's.
  if (e.at === null) return `${what0}; when, who and why weren't recorded.`;
  const at = short(e.at, now);
  const p = provider ?? "The provider";
  const cadence =
    e.cause !== null && isKnown(e.cause) && e.cause !== "operator"
      ? CADENCE_CANCELS[e.cause]
      : undefined;
  if (cadence) return `Canceled by Cadence at ${at}: ${cadence(p)}${providerReason(e)}.`;
  if (e.by === null) return `${what0} at ${at}; who and why weren't recorded.`;
  if (e.by?.kind !== "user" || e.cause === null || !isKnown(e.cause))
    return `${what0} by Cadence at ${at}.`;
  const who = e.by.name ?? "an operator";
  const what = e.kind === "ended_early" ? "Ended early" : "Canceled";
  return e.reason ? `${what} by ${who} at ${at}${quoted(e.reason)}` : `${what} by ${who} at ${at}.`;
}

/** The pass's state tag once Cadence's side stopped: CANCELED / ENDED EARLY (off). */
export const endedTag = (e: ContactEnded | null | undefined) =>
  e
    ? { state: "off" as const, label: e.kind === "ended_early" ? "Ended early" : "Canceled" }
    : null;

export type ContactAction = "cancel" | "end";

/** `Cancel EARENDIL-007's PUQ 13:04Z contact?` / `End … contact now?` */
export function sheetTitle(action: ContactAction, spacecraft: string, pass: Pass, now: Date) {
  const station = pass.station.code ?? pass.station.name;
  const label = [station, short(pass.starts_at, now)].filter(Boolean).join(" ");
  return action === "cancel"
    ? `Cancel ${spacecraft}'s ${label} contact?`
    : `End ${spacecraft}'s ${label} contact now?`;
}

/** The commands line, or null with none queued (domain: neither action cancels them). */
export function commandsLine(
  action: ContactAction,
  spacecraft: string,
  q: QueuedCommands | null | undefined,
  now: Date,
): string | null {
  if (!q || q.count === 0) return null;
  const next = q.next_contact;
  const where = next
    ? ` (${[next.station.code ?? next.station.name, short(next.starts_at, now)].filter(Boolean).join(" ")})`
    : "";
  const head =
    action === "cancel"
      ? `${plural(q.count, "queued command request")} ${q.count === 1 ? "waits" : "wait"} for ${spacecraft}'s next contact`
      : `Uplinks already sent stay sent. ${plural(q.count, "queued request")} ${q.count === 1 ? "waits" : "wait"} for the next contact`;
  const tail = next ? `${where}.` : "; none is scheduled yet.";
  const e = q.expiring_before_next;
  const expires =
    e && e.count > 0
      ? q.count === 1
        ? ` It expires at ${short(e.earliest_at, now)}, before then.`
        : e.count === 1
          ? ` 1 of them expires at ${short(e.earliest_at, now)}, before then.`
          : ` ${e.count} of them expire before then, the first at ${short(e.earliest_at, now)}.`
      : "";
  return `${head}${tail}${expires}`;
}

/** The sheet's consequence lines, in ux's order: what stops, the booking, the commands. */
export function consequenceLines(
  action: ContactAction,
  pass: Pass,
  spacecraft: string,
  queued: QueuedCommands | null | undefined,
  mayRelease: boolean,
  now: Date,
): readonly string[] {
  const provider = pass.source.provider_name ?? "The provider";
  const stops =
    action === "cancel"
      ? "Cadence won't open this contact: nothing is received or sent on it."
      : "Cadence stops receiving and sending now. Telemetry from the rest of this pass won't be received.";
  const booking =
    action === "cancel"
      ? `${provider}'s booking isn't changed.${mayRelease ? " If you don't want the pass either, release it after this." : ""}`
      : `${provider}'s booking isn't changed: the provider may keep flying the pass until LOS ${short(pass.ends_at, now)}.`;
  return [stops, booking, commandsLine(action, spacecraft, queued, now)].filter(
    (l): l is string => l !== null,
  );
}

export const NO_ACCESS_CONTACT = "Operators can cancel or end contacts.";
export const REASON_HELP = "Recorded with your name and the time.";
export const REASON_PLACEHOLDER = "e.g. Its booking failed, so there's nothing to listen to.";
export const REASON_MAX = 500;

const notCancelable = d.object({ state: d.knownText(["active", "ended", "canceled"] as const) });
const notLive = d.object({ state: d.knownText(["not_started", "ended", "canceled"] as const) });

/** ux U55 refusal words; the caller re-reads the pass after each. */
export function refusalWords(e: ApiError): string {
  if (isError(e, "contact_not_cancelable")) {
    const s = detailsOf(e, notCancelable)?.state;
    return s === "active"
      ? "Not canceled: the contact started meanwhile. End it now instead."
      : "Not canceled: the contact has already ended.";
  }
  if (isError(e, "contact_not_live")) {
    const s = detailsOf(e, notLive)?.state;
    return s === "not_started"
      ? "Not ended: the contact hasn't started. Cancel it instead."
      : s === "canceled"
        ? "Not ended: the contact was canceled."
        : "Not ended: the contact has already ended.";
  }
  if (isError(e, "no_scheduled_contact"))
    return "Not canceled: this pass has no contact in Cadence.";
  if (isError(e, "pass_not_found")) return "Not canceled: the contact wasn't found.";
  if (e.kind === "forbidden") return NO_ACCESS_CONTACT;
  return describeApiError(e);
}

/** POST …/passes/:id/cancel-contact or …/end-contact {reason} → the pass row. */
export function stopContact(
  missionId: MissionId,
  passId: string,
  action: ContactAction,
  reason: string,
) {
  return request(
    `/missions/${encodeURIComponent(missionId)}/passes/${encodeURIComponent(passId)}/${action === "cancel" ? "cancel-contact" : "end-contact"}`,
    passReader,
    { method: "POST", body: { reason } },
  );
}
