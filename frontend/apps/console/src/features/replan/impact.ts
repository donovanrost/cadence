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
      why: why(p),
    })),
    passes: lost.length,
    spacecraft: new Set(lost.map((p) => p.spacecraft_id)).size,
    stations,
    truncated,
  };
}
