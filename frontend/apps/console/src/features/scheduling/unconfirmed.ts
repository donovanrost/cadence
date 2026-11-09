import { formatCount, plural } from "@/ui";
import { stationCode, type PlanDetail } from "./api.ts";
import type { SpacecraftName } from "./names.ts";

export type UnconfirmedRow = Readonly<{
  id: string;
  /** `EARENDIL-001 · KIR · 00:12Z` */
  text: string;
  startsAt: Date;
}>;

/**
 * U30: what K1 and K2 say about placed bookings a provider hasn't answered past its window.
 * Null when there are none. The copy claims only what's known (U20): maybe booked, not re-sent.
 */
export function unconfirmedView(
  plan: PlanDetail,
  nameOf: (id: string | null) => SpacecraftName | null,
): { headline: string; rows: UnconfirmedRow[]; count: number } | null {
  const u = plan.unconfirmed;
  if (!u || u.passes.length === 0) return null;
  const n = u.passes.length;
  const byProvider = new Map<string, number>();
  for (const p of u.passes) {
    const name = p.provider.name ?? "an unnamed provider";
    byProvider.set(name, (byProvider.get(name) ?? 0) + 1);
  }
  const minutes = Math.max(Math.round(u.window_ms / 60_000), 1);
  const bookings = plural(n, "booking");
  const headline =
    byProvider.size === 1
      ? `${[...byProvider.keys()][0] ?? "The provider"} hasn't confirmed ${bookings} after ${minutes} min. They may or may not be booked, so Cadence won't send them again. Check them with ${[...byProvider.keys()][0] ?? "the provider"}.`
      : `Providers haven't confirmed ${bookings} (${[...byProvider.entries()].map(([name, c]) => `${name} ${c}`).join(", ")}) after ${minutes} min. They may or may not be booked, so Cadence won't send them again. Check them with each provider.`;
  const passes = new Map(plan.passes.map((p) => [p.snapshot_id, p]));
  const rows = u.passes.flatMap((x) => {
    const p = passes.get(x.snapshot_id);
    if (!p) return [];
    const who = nameOf(p.spacecraft_id)?.name ?? p.spacecraft_id ?? "unknown spacecraft";
    return [
      {
        id: x.snapshot_id,
        text: `${who} · ${stationCode(p.station)} · ${p.starts_at.slice(11, 16)}Z`,
        startsAt: new Date(p.starts_at),
      },
    ];
  });
  rows.sort((a, b) => a.startsAt.getTime() - b.startsAt.getTime());
  return { headline, rows, count: n };
}

/** U30 header suffix: `· 4 unconfirmed` (the unconfirmed state itself leads with the booked count). */
export function unconfirmedTail(plan: PlanDetail): string | null {
  const u = plan.unconfirmed;
  if (!u || u.passes.length === 0) return null;
  return plan.state === "unconfirmed"
    ? `${formatCount(u.booked)} booked · ${formatCount(u.passes.length)} unconfirmed`
    : `${formatCount(u.passes.length)} unconfirmed`;
}
