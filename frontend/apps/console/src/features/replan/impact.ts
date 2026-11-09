import type { Pass } from "@/features/contacts/index.ts";

/** Reservation states that a re-plan after provider changes repairs (DECISIONS #25). */
export const lostStates = ["rejected", "failed", "canceled", "unknown"] as const;
type LostState = (typeof lostStates)[number];
const isLost = (s: string): s is LostState => lostStates.some((x) => x === s);

export type ImpactRow = Readonly<{
  id: string;
  spacecraft: string;
  station: string;
  startsAt: string;
  endsAt: string;
  why: string;
}>;
export type Impact = Readonly<{
  rows: readonly ImpactRow[];
  passes: number;
  spacecraft: number;
  stations: readonly string[];
  truncated: boolean;
}>;

function why(p: Pass & { state: LostState }): string {
  const provider = p.source.provider_name ?? "the provider";
  switch (p.state) {
    case "rejected":
      return `Rejected by ${provider}`;
    case "failed":
      return `Booking with ${provider} failed`;
    case "canceled":
      return `Canceled by ${provider}`;
    case "unknown":
      return `State unknown at ${provider}`;
  }
}

/** The live plan's bookings that didn't hold: what A Impact lists in v1 (no station status yet). */
export function impactOf(passes: readonly Pass[], planId: string, truncated: boolean): Impact {
  const lost = passes.flatMap((p) =>
    p.plan?.id === planId && isLost(p.state) ? [{ ...p, state: p.state }] : [],
  );
  const stations = [...new Set(lost.map((p) => p.station.code ?? p.station.ref ?? "—"))].sort();
  return {
    rows: lost.map((p) => ({
      id: p.id,
      spacecraft: p.spacecraft?.name ?? p.spacecraft_id ?? "Unknown spacecraft",
      station: p.station.code ?? p.station.ref ?? "—",
      startsAt: p.starts_at,
      endsAt: p.ends_at,
      why: why(p),
    })),
    passes: lost.length,
    spacecraft: new Set(lost.map((p) => p.spacecraft_id)).size,
    stations,
    truncated,
  };
}

/**
 * The window a re-plan should cover: the lost bookings' span, never starting in the past. Without
 * one the server repairs now → end of horizon, which can exceed the policy's repair window
 * (422 fleet_repair_horizon_exceeded).
 */
export function lostWindow(
  rows: readonly Readonly<{ startsAt: string; endsAt: string }>[],
  now: Date,
): Readonly<{ from: string; to: string }> | null {
  if (rows.length === 0) return null;
  const from = Math.max(now.getTime(), Math.min(...rows.map((r) => Date.parse(r.startsAt))));
  const to = Math.max(...rows.map((r) => Date.parse(r.endsAt)));
  return to > from ? { from: new Date(from).toISOString(), to: new Date(to).toISOString() } : null;
}
