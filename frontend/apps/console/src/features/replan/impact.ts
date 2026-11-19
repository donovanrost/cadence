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
  const by = p.ended_by;
  const person = by?.kind === "user" ? (by.name ?? "an operator") : null;
  switch (p.state) {
    case "rejected":
      return `Rejected by ${provider}`;
    case "failed":
      // #53: an operator's "not booked" fails the item (ended_by is the operator).
      return person ? `Marked not booked by ${person}` : `Booking with ${provider} failed`;
    case "canceled":
      // ux 45099dc0 / U20: name who canceled only when the read says so.
      if (person) return `Canceled by ${person} · at ${provider}`;
      return by?.kind === "provider"
        ? `Canceled by ${by.name ?? provider}`
        : `Canceled at ${provider}`;
    case "unknown":
      return `State unknown at ${provider}`;
  }
}

/**
 * The day's repair chain (qa #30): the plan detail's own `chain` when the server sends it (api
 * 22d83acd); otherwise as far as the passes read shows it: the plan, its parent, and every applied
 * repair that replaced a lost booking of a plan already in the chain.
 */
function chainOf(passes: readonly Pass[], plan: ImpactPlan): Set<string> {
  if (plan.chain && plan.chain.length > 0)
    return new Set([plan.id, ...plan.chain.map((c) => c.id)]);
  const chain = new Set([plan.id, ...(plan.repair_of ? [plan.repair_of.plan.id] : [])]);
  for (let grew = true; grew;) {
    grew = false;
    for (const p of passes) {
      const next = p.replaced_by?.plan_id;
      if (next && p.plan && chain.has(p.plan.id) && !chain.has(next)) {
        chain.add(next);
        grew = true;
      }
    }
  }
  return chain;
}

export type ImpactPlan = Readonly<{
  id: string;
  repair_of: { plan: { id: string } } | null;
  chain?: readonly Readonly<{ id: string }>[] | null | undefined;
}>;

/** The day's bookings that didn't hold and no applied repair replaced: what A Impact lists. */
export function impactOf(passes: readonly Pass[], plan: ImpactPlan, truncated: boolean): Impact {
  const chain = chainOf(passes, plan);
  const lost = passes.flatMap((p) =>
    p.plan && chain.has(p.plan.id) && isLost(p.state) && !p.replaced_by
      ? [{ ...p, state: p.state }]
      : [],
  );
  const stations = [...new Set(lost.map((p) => p.station.code ?? p.station.ref ?? "—"))].sort();
  return {
    rows: lost.map((p) => ({
      id: p.id,
      spacecraft: p.spacecraft?.name ?? "Unknown spacecraft",
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
