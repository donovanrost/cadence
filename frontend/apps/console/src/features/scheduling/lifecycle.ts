import {
  actor,
  decoders as d,
  detailsOf,
  isError,
  spacecraftRef,
  stationId,
  type ApiError,
  type Decoded,
} from "@/api";
import { formatCount, plural } from "@/ui";

/**
 * The day-plan lifecycle (U61; domain's proposal, the director's ruling; api's wire 11-15): a new
 * plan for a day replaces a pending one, approval refuses a day another plan already covers, and
 * approval books what's still bookable and reports the passes whose booking window had closed
 * (#273: the provider's window, which can close before AOS, so never "started", U20).
 */

/** Plan read: the plan that replaced this one; null when it wasn't replaced. */
export const supersededByReader = d.nullable(
  d.object({ plan_id: d.token, revision: d.integer, author: d.nullable(actor), at: d.timestamp }),
);
export type SupersededBy = NonNullable<Decoded<typeof supersededByReader>>;

/** #273: a listed pass's station, as the plan read and the approve answer send it ({id, code, name}). */
const expiredStation = d.nullable(
  d.object({
    ref: d.optional(d.nullable(d.string)),
    id: d.optional(d.nullable(stationId)),
    // free-text: a station's short code (SVA), shown as is
    code: d.optional(d.nullable(d.string)),
    name: d.optional(d.nullable(d.string)),
  }),
);

/**
 * #273 (api's final shape): the selected passes whose booking window has closed, on the plan read
 * (before deciding) and the approve answer (the set the decision skipped); null when none. `items`
 * are capped at 5,000 in AOS order, `count` isn't. `reason` no_booking_window: the provider gave no
 * window (domain fails closed, so the pass counts as closed); api 11-19.
 */
export const expiredReader = d.nullable(
  d.object({
    count: d.integer,
    reservable_count: d.integer,
    items: d.array(
      d.object({
        snapshot_id: d.optional(d.token),
        spacecraft: d.nullable(spacecraftRef),
        station: expiredStation,
        aos: d.timestamp,
        expires_at: d.optional(d.nullable(d.timestamp)),
        reason: d.optional(d.knownText(["opportunity_expired", "no_booking_window"] as const)),
      }),
      5_000,
    ),
  }),
);
export type Expired = NonNullable<Decoded<typeof expiredReader>>;

/** Plan states the refusal names; another lifecycle state keeps its server word. */
const coveringStates = ["approved", "executing", "partially_reserved", "reserved"] as const;
const COVERING_WORDS: Readonly<Record<(typeof coveringStates)[number], string>> = {
  approved: "approved",
  executing: "booking",
  partially_reserved: "booked",
  reserved: "booked",
};

const alreadyPlanned = d.object({
  plan_id: d.token,
  revision: d.integer,
  state: d.knownText(coveringStates),
  requirements: d.integer,
  day: d.string,
});
const replaced = d.object({ plan_id: d.token, revision: d.integer, at: d.timestamp });
/** All closed (#273): the closed set, `{expired, expired_digest}`. */
const allExpired = d.object({ expired: d.optional(expiredReader) });

/** `11-16` from `2026-11-16`. */
export const dayLabel = (day: string) => day.slice(5, 10);

/** `10:05Z`, with the date before it when it isn't `now`'s UTC day (§4). */
function at(iso: string, now: Date): string {
  const time = `${iso.slice(11, 16)}Z`;
  return iso.slice(0, 10) === now.toISOString().slice(0, 10) ? time : `${iso.slice(5, 10)} ${time}`;
}

const revisionBy = (revision: number, author: SupersededBy["author"]) =>
  `R${revision}${author?.name ? ` (${author.name})` : ""}`;

/** A superseded plan's state line: "Superseded by R44 (Mira K.) at 10:05Z." */
export const supersededByLine = (s: SupersededBy, now: Date = new Date()) =>
  `Superseded by ${revisionBy(s.revision, s.author)} at ${at(s.at, now)}.`;

/** Where a refusal points: the plan to open. */
export type LifecycleRefusal = Readonly<{
  text: string;
  /** The plan to open; `day` when the refusal names it (else the day on screen). */
  open: Readonly<{ planId: string; label: string; day: string | null }> | null;
}>;

/** The three U61 approval refusals in ux's words; null for any other error. */
export function lifecycleRefusal(error: ApiError, now: Date = new Date()): LifecycleRefusal | null {
  if (isError(error, "contact_plan_day_already_planned")) {
    const p = detailsOf(error, alreadyPlanned);
    if (!p)
      return {
        text: "Not approved: another plan already covers this day.",
        open: null,
      };
    const state = typeof p.state === "string" ? COVERING_WORDS[p.state] : p.state.unrecognized;
    return {
      text: `Not approved: R${p.revision} (${state}) already covers ${formatCount(p.requirements)} of these requirements for ${dayLabel(p.day)}. Open R${p.revision}, or send this plan back.`,
      open: { planId: p.plan_id, label: `Open R${p.revision}`, day: p.day },
    };
  }
  if (isError(error, "contact_plan_replaced")) {
    const p = detailsOf(error, replaced);
    return p
      ? {
          text: `Not approved: R${p.revision} replaced this plan at ${at(p.at, now)}.`,
          open: { planId: p.plan_id, label: `Open R${p.revision}`, day: null },
        }
      : { text: "Not approved: a newer plan replaced this one.", open: null };
  }
  if (isError(error, "contact_plan_all_opportunities_expired")) {
    const p = detailsOf(error, allExpired);
    const n = p?.expired?.count ?? null;
    return {
      text: `Not approved: the booking window has closed for ${allPasses(n)}, so nothing could be booked.`,
      open: null,
    };
  }
  return null;
}

/** #273: "all 36 of its passes", "its only pass", or "all its passes" without a count. */
export const allPasses = (n: number | null) =>
  n === null ? "all its passes" : n === 1 ? "its only pass" : `all ${formatCount(n)} of its passes`;

/** Partial approval: "Approved. Booking 1,476 passes; 36 weren't booked because their booking window had closed." */
export function partialApproval(e: Expired): string {
  const left =
    e.count === 1
      ? "1 wasn't booked because its booking window had closed"
      : `${formatCount(e.count)} weren't booked because their booking window had closed`;
  return `Approved. Booking ${plural(e.reservable_count, "pass", "passes")}; ${left}.`;
}

/**
 * One left-out pass under `Show 36`: `EARENDIL-001 · SVA · AOS 00:10Z`; no close time (#273). A pass
 * the provider gave no window adds "No booking window from the provider".
 */
export function expiredLine(item: Expired["items"][number], now: Date = new Date()): string {
  const station = item.station?.code ?? item.station?.name ?? item.station?.ref ?? null;
  return [
    item.spacecraft ? (item.spacecraft.name ?? "Unknown spacecraft") : null,
    station,
    `AOS ${at(item.aos, now)}`,
    noWindow(item) ? "No booking window from the provider" : null,
  ]
    .filter((p): p is string => p !== null)
    .join(" · ");
}

/** U61/#341: keyed on the item's `reason` only; an unknown or absent reason adds nothing. */
export const noWindow = (item: Expired["items"][number]) => item.reason === "no_booking_window";

/** K1 opened on one plan of the day (`?plan=`), for a refusal's or a superseded line's Open. */
export const planOfDayRoute = (day: string, planId: string) => ({
  name: "ops.contacts.plan" as const,
  query: { day, plan: planId },
});
