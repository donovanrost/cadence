import { formatCount, plural } from "@/ui";
import { stationCode, type PlanDetail } from "./api.ts";
import type { SpacecraftName } from "./names.ts";

/** One unconfirmed pass, as listed and as handed to the `row-actions` slot (U32, fe-setup). */
export type UnconfirmedPass = Readonly<{
  snapshot_id: string;
  provider: Readonly<{ id: string; name: string | null }> | null;
  sent_at: string;
  /** Spacecraft name (or id when unnamed), station code, AOS: what the row shows. */
  spacecraft: string;
  station: string;
  startsAt: Date;
  /** `03:00Z` today (UTC), `11-15 03:00Z` on another day (design language §4). */
  when: string;
  /** `EARENDIL-001 · KIR · 03:00Z` */
  text: string;
}>;

/** §4 short time: `03:00Z` on `today` (YYYY-MM-DD, UTC), else `11-15 03:00Z`. */
export function shortWhen(iso: string, today: string): string {
  const time = `${iso.slice(11, 16)}Z`;
  return iso.slice(0, 10) === today ? time : `${iso.slice(5, 10)} ${time}`;
}

/**
 * U30: what K1 and K2 say about placed bookings a provider hasn't answered past its window.
 * Null when there are none. The copy claims only what's known (U20): maybe booked, not re-sent.
 */
export function unconfirmedView(
  plan: PlanDetail,
  nameOf: (id: string | null) => SpacecraftName | null,
  today: string,
): { headline: string; passes: UnconfirmedPass[]; count: number } | null {
  const u = plan.unconfirmed;
  if (!u || u.passes.length === 0) return null;
  const n = u.passes.length;
  const byProvider = new Map<string, number>();
  for (const p of u.passes) {
    const name = p.provider?.name ?? "an unnamed provider";
    byProvider.set(name, (byProvider.get(name) ?? 0) + 1);
  }
  const minutes = Math.max(Math.round(u.window_ms / 60_000), 1);
  const bookings = plural(n, "booking");
  const only = byProvider.size === 1 ? [...byProvider.keys()][0] : undefined;
  const headline = only
    ? `${only} hasn't confirmed ${bookings} after ${minutes} min. They may or may not be booked, so Cadence won't send them again. Check them with ${only}.`
    : `Providers haven't confirmed ${bookings} (${[...byProvider.entries()].map(([name, c]) => `${name} ${c}`).join(", ")}) after ${minutes} min. They may or may not be booked, so Cadence won't send them again. Check them with each provider.`;
  const byId = new Map(plan.passes.map((p) => [p.snapshot_id, p]));
  const passes = u.passes.flatMap((x): UnconfirmedPass[] => {
    const p = byId.get(x.snapshot_id);
    if (!p) return [];
    const spacecraft = nameOf(p.spacecraft_id)?.name ?? p.spacecraft_id ?? "unknown spacecraft";
    const station = stationCode(p.station);
    const when = shortWhen(p.starts_at, today);
    return [
      {
        ...x,
        spacecraft,
        station,
        startsAt: new Date(p.starts_at),
        when,
        text: `${spacecraft} · ${station} · ${when}`,
      },
    ];
  });
  passes.sort((a, b) => a.startsAt.getTime() - b.startsAt.getTime());
  return { headline, passes, count: n };
}

/** U30 header suffix: `· 4 unconfirmed` (the unconfirmed state itself leads with the booked count). */
export function unconfirmedTail(plan: PlanDetail): string | null {
  const u = plan.unconfirmed;
  if (!u || u.passes.length === 0) return null;
  const n = `${formatCount(u.passes.length)} unconfirmed`;
  if (plan.state === "unconfirmed") return `${formatCount(u.booked)} booked · ${n}`;
  // ux: 'R41 · 1,490 OF 1,512 BOOKED · 4 UNCONFIRMED'.
  if (plan.state === "partially_reserved")
    return `${formatCount(u.booked)} of ${formatCount(plan.counts.passes)} booked · ${n}`;
  return n;
}
