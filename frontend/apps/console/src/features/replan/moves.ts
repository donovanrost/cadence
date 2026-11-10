import { formatDuration } from "@/ui";
import { stationCode, type Repair } from "@/features/scheduling/index.ts";

type Move = NonNullable<Repair["diff"]>["moved"][number];

/**
 * C · Changes move line (ux): a pass re-planned onto the same station and start is a re-booking of
 * the lost pass, not a move ("re-booked · KIR 00:54Z"); otherwise "KIR 00:54Z → SVA 02:40Z".
 * The offset shows only when it isn't zero. Repair passes carry no antenna, so none is named.
 */
export function moveLine(m: Move): Readonly<{ route: string; offset: string | null }> {
  const from = `${stationCode(m.from.station)} ${m.from.starts_at.slice(11, 16)}Z`;
  const to = `${stationCode(m.to.station)} ${m.to.starts_at.slice(11, 16)}Z`;
  if (from === to && m.from.starts_at === m.to.starts_at)
    return { route: `· re-booked · ${to}`, offset: null };
  const s = m.offset_s;
  return {
    route: `${from} → ${to}`,
    offset: s === 0 ? null : s > 0 ? `+${formatDuration(s)}` : `−${formatDuration(-s)}`,
  };
}
