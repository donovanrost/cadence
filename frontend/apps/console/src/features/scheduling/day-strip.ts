import { decoders as d, request, type ApiResult, type Decoded, type MissionId } from "@/api";
import { formatCount } from "@/ui";
import { planStates, type PlanState } from "./api.ts";

/**
 * K1's day strip (DECISIONS #100, A14; ScheduleFlow §K1 day strip; api 901cd1e0d): the next 7 UTC
 * days, today first, each with its newest plan's state in U61's words, so the strip and Now agree.
 */

const planState = (value: unknown, path?: string): PlanState => {
  const s = d.string(value, path);
  return planStates.find((c) => c === s) ?? "unrecognized";
};

const dayRow = d.object({
  day: d.string,
  plan: d.nullable(d.object({ id: d.token, version: d.integer, state: planState })),
  sent_back: d.boolean,
  requirements_count: d.integer,
  booked_count: d.nullable(d.integer),
  unconfirmed_count: d.nullable(d.integer),
  requested_count: d.optional(d.nullable(d.integer)),
  /** U61's plan_coverage first window; null until that source lands (api). */
  first_window_at: d.nullable(d.timestamp),
});
export const planDaysReader = d.object({ days: d.array(dayRow, 14) });
export type PlanDay = Decoded<typeof dayRow>;

export function fetchPlanDays(
  missionId: MissionId,
  from: string,
  to: string,
  signal?: AbortSignal,
): Promise<ApiResult<Decoded<typeof planDaysReader>>> {
  return request(
    `/missions/${encodeURIComponent(missionId)}/contact-plans/days?from=${from}&to=${to}`,
    planDaysReader,
    signal ? { signal } : {},
  );
}

const DAY = 86_400_000;
/** The strip's 7 UTC days, today first. */
export function stripDays(now: Date): readonly string[] {
  const today = Date.parse(`${now.toISOString().slice(0, 10)}T00:00:00Z`);
  return Array.from({ length: 7 }, (_, i) => new Date(today + i * DAY).toISOString().slice(0, 10));
}

const weekday = (day: string, month: boolean) =>
  new Date(`${day}T00:00:00Z`).toLocaleDateString("en-GB", {
    weekday: "short",
    day: "numeric",
    ...(month ? { month: "short" } : {}),
    timeZone: "UTC",
  });
/** `Tue 17` in the cell; `Tue 17 Nov` in its accessible name. */
export const cellDay = (day: string) => weekday(day, false).replace(",", "");
const longDay = (day: string) => weekday(day, true).replace(",", "");

export type MarkState = "nominal" | "caution" | "crit";
export type StripCell = Readonly<{
  day: string;
  label: string;
  word: string;
  mark: Readonly<{ glyph: "■" | "▲" | "◆"; state: MarkState }> | null;
  name: string;
}>;

const NOMINAL = { glyph: "■", state: "nominal" } as const;
const CAUTION = { glyph: "▲", state: "caution" } as const;
const CRIT = { glyph: "◆", state: "crit" } as const;

/** Unbooked states take U61's thresholds: ▲ from T−24h, ◆ 'Started unplanned' once the window opens. */
function unbooked(word: string, first: string | null, now: Date) {
  if (!first) return { word, mark: null };
  const t = Date.parse(first);
  if (now.getTime() >= t) return { word: "Started unplanned", mark: CRIT };
  if (now.getTime() >= t - DAY) return { word, mark: CAUTION };
  return { word, mark: null };
}

function wordFor(d: PlanDay, now: Date): Pick<StripCell, "word" | "mark"> {
  const p = d.plan;
  if (!p)
    return d.requirements_count === 0
      ? { word: "Nothing to plan", mark: null }
      : unbooked("No plan", d.first_window_at, now);
  switch (p.state) {
    case "reserved":
      return { word: "Booked", mark: NOMINAL };
    case "partially_reserved":
      return {
        word:
          d.booked_count !== null && d.requested_count != null
            ? `${formatCount(d.booked_count)} of ${formatCount(d.requested_count)} booked`
            : "Partly booked",
        mark: CAUTION,
      };
    case "failed":
      return { word: "Booking failed", mark: CAUTION };
    case "unconfirmed":
      return {
        word:
          d.unconfirmed_count !== null
            ? `${formatCount(d.unconfirmed_count)} unconfirmed`
            : "Unconfirmed",
        mark: CAUTION,
      };
    // ux 52b4c039e: approved, nothing sent yet; 'Booking…' would claim work that may not be happening (U20).
    // …and takes U61's marks (ux 366240d64): an approved plan that hasn't booked leaves the day open.
    case "approved":
      return unbooked("Approved", d.first_window_at, now);
    case "executing":
      return { word: "Booking…", mark: null };
    case "pending_approval":
      return unbooked("Awaiting approval", d.first_window_at, now);
    // ux U61 (366240d64): a plan whose booking stopped, with what it booked of what it books.
    case "interrupted":
      return {
        word:
          d.booked_count !== null && d.requested_count != null
            ? `Booking stopped · ${formatCount(d.booked_count)} of ${formatCount(d.requested_count)}`
            : "Booking stopped",
        mark: CAUTION,
      };
    case "draft":
    case "superseded":
      return unbooked(d.sent_back ? "Sent back" : "Draft", d.first_window_at, now);
    // The day's rule skips canceled plans; one that slips through reads as no plan.
    case "canceled":
      return unbooked("No plan", d.first_window_at, now);
    case "unrecognized":
      return { word: "Plan", mark: null };
  }
}

export function stripCell(d: PlanDay, now: Date = new Date()): StripCell {
  const w = wordFor(d, now);
  const firstWindow = d.first_window_at ? `, first window ${d.first_window_at.slice(11, 16)}Z` : "";
  return {
    day: d.day,
    label: cellDay(d.day),
    ...w,
    name: `${longDay(d.day)}: ${w.word.toLowerCase()}${firstWindow}`,
  };
}
