import {
  actor,
  decoders as d,
  detailsOf,
  isError,
  spacecraftRef,
  stationRef,
  type ApiError,
  type Decoded,
} from "@/api";
import { formatCount, plural } from "@/ui";

/**
 * The day-plan lifecycle (U61; domain's proposal, the director's ruling; api's wire 11-15): a new
 * plan for a day replaces a pending one, approval refuses a day another plan already covers, and
 * approval books what's still bookable and reports the passes that had already started.
 */

/** Plan read: the plan that replaced this one; null when it wasn't replaced. */
export const supersededByReader = d.nullable(
  d.object({ plan_id: d.token, revision: d.integer, author: d.nullable(actor), at: d.timestamp }),
);
export type SupersededBy = NonNullable<Decoded<typeof supersededByReader>>;

/** The submit/approve answer: passes left out because their window had started; null when none. */
export const expiredReader = d.nullable(
  d.object({
    count: d.integer,
    reservable_count: d.integer,
    items: d.array(
      d.object({
        spacecraft: d.nullable(spacecraftRef),
        station: d.nullable(stationRef),
        aos: d.timestamp,
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
const allExpired = d.object({ expired_count: d.integer, day: d.string });

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

/** Where a refusal points: the plan to open, or the day to plan the rest of. */
export type LifecycleRefusal = Readonly<{
  text: string;
  /** The plan to open; `day` when the refusal names it (else the day on screen). */
  open: Readonly<{ planId: string; label: string; day: string | null }> | null;
  planRestOf: string | null;
}>;

/** The three U61 approval refusals in ux's words; null for any other error. */
export function lifecycleRefusal(error: ApiError, now: Date = new Date()): LifecycleRefusal | null {
  if (isError(error, "contact_plan_day_already_planned")) {
    const p = detailsOf(error, alreadyPlanned);
    if (!p)
      return {
        text: "Not approved: another plan already covers this day.",
        open: null,
        planRestOf: null,
      };
    const state = typeof p.state === "string" ? COVERING_WORDS[p.state] : p.state.unrecognized;
    return {
      text: `Not approved: R${p.revision} (${state}) already covers ${formatCount(p.requirements)} of these requirements for ${dayLabel(p.day)}. Open R${p.revision}, or send this plan back.`,
      open: { planId: p.plan_id, label: `Open R${p.revision}`, day: p.day },
      planRestOf: null,
    };
  }
  if (isError(error, "contact_plan_replaced")) {
    const p = detailsOf(error, replaced);
    return p
      ? {
          text: `Not approved: R${p.revision} replaced this plan at ${at(p.at, now)}.`,
          open: { planId: p.plan_id, label: `Open R${p.revision}`, day: null },
          planRestOf: null,
        }
      : { text: "Not approved: a newer plan replaced this one.", open: null, planRestOf: null };
  }
  if (isError(error, "contact_plan_all_opportunities_expired")) {
    const p = detailsOf(error, allExpired);
    const all = p
      ? `all ${formatCount(p.expired_count)} of its passes have`
      : "its passes have all";
    return {
      text: `Not approved: ${p?.expired_count === 1 ? "its only pass has" : all} already started, so nothing could be booked.`,
      open: null,
      planRestOf: p?.day ?? null,
    };
  }
  return null;
}

/** Partial approval: "Approved. Booking 1,476 passes; 36 had already started, so they weren't booked." */
export function partialApproval(e: Expired): string {
  const left =
    e.count === 1
      ? "1 had already started, so it wasn't booked"
      : `${formatCount(e.count)} had already started, so they weren't booked`;
  return `Approved. Booking ${plural(e.reservable_count, "pass", "passes")}; ${left}.`;
}

/** One left-out pass under `Show 36`: `EARENDIL-001 · SVA · AOS 00:10Z`. */
export function expiredLine(item: Expired["items"][number], now: Date = new Date()): string {
  const station = item.station?.code ?? item.station?.name ?? item.station?.ref ?? null;
  return [item.spacecraft?.name ?? item.spacecraft?.id ?? null, station, `AOS ${at(item.aos, now)}`]
    .filter((p): p is string => p !== null)
    .join(" · ");
}

/** K1 opened on one plan of the day (`?plan=`), for a refusal's or a superseded line's Open. */
export const planOfDayRoute = (day: string, planId: string) => ({
  name: "ops.contacts.plan" as const,
  query: { day, plan: planId },
});
