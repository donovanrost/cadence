import { formatDuration } from "@/ui";
import { stationCode, type Repair } from "@/features/scheduling/index.ts";

type Move = NonNullable<Repair["diff"]>["moved"][number];

/** Re-planned onto the same station and start: a re-booking of the lost pass in its own window. */
export const sameWindow = (m: Move) =>
  stationCode(m.from.station) === stationCode(m.to.station) && m.from.starts_at === m.to.starts_at;

/**
 * C · Changes move line (ux): a same-window move reads "· KIR 00:54Z · same window, re-booked"
 * (still counted under Moved, which is what Apply sends); otherwise "KIR 00:54Z → SVA 02:40Z".
 * The offset shows only when it isn't zero. Repair passes carry no antenna, so none is named.
 */
export function moveLine(m: Move): Readonly<{ route: string; offset: string | null }> {
  const from = `${stationCode(m.from.station)} ${m.from.starts_at.slice(11, 16)}Z`;
  const to = `${stationCode(m.to.station)} ${m.to.starts_at.slice(11, 16)}Z`;
  if (from === to && m.from.starts_at === m.to.starts_at)
    return { route: `· ${to} · same window, re-booked`, offset: null };
  const s = m.offset_s;
  return {
    route: `${from} → ${to}`,
    offset: s === 0 ? null : s > 0 ? `+${formatDuration(s)}` : `−${formatDuration(-s)}`,
  };
}
