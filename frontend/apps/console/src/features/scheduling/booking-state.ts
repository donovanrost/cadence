import { isKeyOf, isKnown } from "@/api";
import { formatHourMinute, type GanttBarKind } from "@/ui";
import { stationCode, type BookingState, type PlanPass, type PlanState } from "./api.ts";

/**
 * K1 executing: each drafted bar shows its own booking (api 8e), Requested → Confirmed /
 * Rejected (ScheduleFlow K1 `executing`). Words go with every look (never colour alone).
 */
export type BookingLook = Readonly<{ kind: GanttBarKind; word: string }>;

const LOOKS: Readonly<Record<BookingState, BookingLook>> = {
  never_sent: { kind: "scheduled", word: "Requested" },
  confirmed: { kind: "own", word: "Confirmed" },
  uncertain: { kind: "unconfirmed", word: "Unconfirmed" },
  rejected: { kind: "clash", word: "Rejected" },
  failed: { kind: "problem", word: "Failed" },
};

/** Null before execution, and for a state this console doesn't know (drawn as drafted). */
export function bookingLook(booking: PlanPass["booking"]): BookingLook | null {
  if (!booking || !isKnown(booking.state)) return null;
  const look = LOOKS[booking.state];
  // compared-as-text: booking reasons are provider and Cadence codes, an open set; 'sending' is Cadence's in-flight marker
  return booking.state === "never_sent" && booking.reason === "sending"
    ? { ...look, word: "Requested · sending" }
    : look;
}

type Next = "replan" | "account" | "setup";
const REPLAN: Next = "replan";
const SETUP: Next = "setup";
const ACCOUNT: Next = "account";

/**
 * ux K1 booking reasons (ScheduleFlow, f05d68e9): the reason text and the next step shown. Keyed by
 * the codes the console words (rule A); a provider's own code reads through reasonWords' fallbacks.
 */
const REASONS = {
  no_capacity: ["the station has no capacity then", REPLAN],
  conflict: ["it clashes with another booking at the provider", REPLAN],
  invalid_request: ["the provider refused the request as invalid", null],
  provider_unavailable: ["the provider couldn't be reached", null],
  authentication_failed: ["the provider didn't accept Cadence's credentials", ACCOUNT],
  authorization_failed: ["the provider account isn't allowed to book this", ACCOUNT],
  unsupported_capability: ["the provider doesn't offer this kind of pass", null],
  not_found: ["the provider doesn't know this pass or station", null],
  provider_not_ready: ["the provider wasn't ready to take bookings", null],
  rate_limited: ["the provider asked Cadence to slow down", null],
  known_timeout: ["the provider didn't answer in time", null],
  ambiguous_outcome: ["the provider's answer didn't say whether it's booked", null],
  malformed_response: ["the provider's answer couldn't be read", null],
  provider_error: ["the provider reported an error", null],
  contact_plan_execution_opportunity_expired: ["the window passed before it was sent", REPLAN],
  contact_plan_execution_snapshot_not_found: [
    "the pass isn't in the plan's opportunities any more",
    REPLAN,
  ],
  contact_plan_execution_route_changed: ["its route changed after the plan was drafted", REPLAN],
  contact_plan_execution_route_not_ready: ["its route isn't ready yet", null],
  mission_provider_not_found: ["this mission has no provider set up for that station", SETUP],
  // ground #986: a scheduling refusal once the mission's provider is archived.
  mission_provider_archived: ["this mission's provider for that station is archived", SETUP],
  provider_account_version_not_found: ["the provider account's settings are missing", SETUP],
  provider_account_grant_not_found: ["this mission isn't granted the provider account", SETUP],
  provider_account_grant_revoked: [
    "this mission's access to the provider account was revoked",
    SETUP,
  ],
  credential_reference_not_found: ["the provider credentials can't be found", SETUP],
  invalid_provider_context: ["the provider setup for this mission isn't valid", SETUP],
  booking_lost: ["the provider dropped a confirmed booking", REPLAN],
  provider_canceled: ["the provider canceled it", REPLAN],
  provider_reservation_not_found: ["the provider has no record of the booking", REPLAN],
  provider_configuration_failure: ["the provider setup failed", SETUP],
  provider_rejected: ["the provider rejected it", null],
  provider_failed: ["the provider couldn't book it", null],
} as const satisfies Readonly<Record<string, readonly [string, Next | null]>>;
/** Operator resolutions: "marked not booked by Mira K. at 10:52Z" (U29; else "by an operator"). */
const OPERATOR = {
  operator_not_booked: "marked not booked",
  operator_rejected: "marked rejected",
  operator_not_sent: "marked not sent",
} as const;
/** Codes that mean Cadence built a bad request: say so, and keep the code for Technical details. */
const CADENCE_FIX = new Set([
  "missing_provider_booking_field",
  "invalid_provider_booking_field",
  "invalid_provider_booking",
  "invalid_contact_interval",
  "unknown_provider_client",
  "malformed_provider_booking_result",
  "provider_booking_failed",
]);
const LOST = new Set(["booking_lost", "provider_canceled", "provider_reservation_not_found"]);

type Booking = NonNullable<PlanPass["booking"]>;

export function reasonWords(
  code: string | null | undefined,
  booking?: Booking,
): { text: string; next: Next | null } {
  const quoted = booking?.detail ? ` ("${booking.detail}")` : "";
  if (!code) return { text: `the provider didn't say why${quoted}`, next: null };
  if (isKeyOf(OPERATOR, code)) {
    const operator = OPERATOR[code];
    const r = booking?.resolved;
    const who = r?.by.name ? `by ${r.by.name}` : "by an operator";
    return {
      text: `${operator} ${who}${r ? ` at ${formatHourMinute(new Date(r.at))}` : ""}`,
      next: null,
    };
  }
  if (CADENCE_FIX.has(code))
    return {
      text: "Cadence couldn't build the booking request. This needs a Cadence fix",
      next: null,
    };
  if (isKeyOf(REASONS, code)) {
    const known = REASONS[code];
    return { text: `${known[0]}${quoted}`, next: known[1] };
  }
  // Other status-based answers (domain fix): provider_<status>.
  if (code.startsWith("provider_"))
    return {
      text: `the provider answered "${code.slice(9).replaceAll("_", " ")}"${quoted}`,
      next: null,
    };
  return { text: `${code.replaceAll("_", " ")}${quoted}`, next: null };
}

/** Only when the read says so (api 8e): rows without a next step may say how retrying goes. */
export function retryWords(booking: Booking): string | null {
  if (booking.retryable === true) {
    const at =
      booking.at && booking.retry_after_seconds != null
        ? new Date(Date.parse(booking.at) + booking.retry_after_seconds * 1000)
        : null;
    return at ? `Cadence retries at ${formatHourMinute(at)}.` : "It can be retried.";
  }
  return booking.retryable === false ? "Retrying won't help." : null;
}

/** The row's word is the bar's state (ux): Rejected, Failed, Lost, Not sent. */
function rowWord(state: BookingState, reason: string | null | undefined): string | null {
  if (state === "rejected") return "Rejected";
  if (state === "failed") return reason && LOST.has(reason) ? "Lost" : "Failed";
  if (state === "never_sent" && reason && reason !== "sending") return "Not sent";
  return null;
}

/**
 * Rejections, failures, losses and stopped sends lead Demand (ScheduleFlow K1): `<Word> · SVB-1
 * 03:00Z: <reason>.` plus the next step. Unconfirmed passes have their own U30 callout.
 */
export function rejectedRows(passes: readonly PlanPass[]) {
  return passes.flatMap((p) => {
    const b = p.booking;
    const word = b && isKnown(b.state) ? rowWord(b.state, b.reason) : null;
    if (!b || !word) return [];
    const { text, next } = reasonWords(b.reason, b);
    const retry = next === null ? retryWords(b) : null;
    return [
      {
        snapshotId: p.snapshot_id,
        spacecraftId: p.spacecraft_id,
        sentence: `${word} · ${stationCode(p.station)} ${p.starts_at.slice(11, 16)}Z: ${text}.${retry ? ` ${retry}` : ""}`,
        next,
        code: b.reason ?? null,
      },
    ];
  });
}

/**
 * qa #52: once a plan has gone out for booking, the screen describes the booking, not the draft:
 * step 04 Reserve, panel B "Plan", and coverage labelled as drafted.
 */
export function isBooking(state: PlanState): boolean {
  switch (state) {
    case "approved":
    case "executing":
    case "partially_reserved":
    case "reserved":
    case "failed":
    case "unconfirmed":
    case "interrupted":
      return true;
    case "draft":
    case "pending_approval":
    case "canceled":
    case "superseded":
    case "unrecognized":
      return false;
  }
}
