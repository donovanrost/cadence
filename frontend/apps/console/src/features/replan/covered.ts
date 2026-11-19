import type { Pass } from "@/features/contacts/index.ts";
import { shortWhen, stationCode, type Repair } from "@/features/scheduling/index.ts";

export type CoveredPass = NonNullable<Repair["diff"]>["covered"][number];

/**
 * domain #56 / ux: a lost booking a separate (unplanned) booking already covers. Not re-sent.
 * `EARENDIL-004 · KIR 00:54Z · covered by a separate booking · KIR 01:10Z`; times per the §4 short
 * rule (date only when not today, UTC). The covering booking is named only when the passes read
 * has it (U20: never invent it).
 */
export function coveredLine(
  c: CoveredPass,
  bookings: readonly Pass[],
  spacecraft: string,
  today: string,
): string {
  const lost = `${spacecraft} · ${stationCode(c.station)} ${shortWhen(c.starts_at, today)}`;
  const by = bookings.find((p) => p.id === c.covered_by);
  const where = by
    ? ` · ${by.station.code ?? by.station.ref ?? "—"} ${shortWhen(by.starts_at, today)}`
    : "";
  return `${lost} · covered by a separate booking${where}`;
}
