import type { RouteLocationRaw } from "vue-router";
import type { Pass } from "./api.ts";

const DAY_MS = 86_400_000;

/**
 * K2: a rejected / failed reservation booked by a plan can be re-planned (lead, 4259c615) while
 * the plan's day hasn't ended (else the pass's own end): History opens passes long past.
 */
export function replanLink(
  p: Pick<Pass, "plan" | "state" | "ends_at"> | null,
  now: number,
): RouteLocationRaw | null {
  if (!p?.plan || (p.state !== "rejected" && p.state !== "failed")) return null;
  const until = p.plan.day ? Date.parse(p.plan.day) + DAY_MS : Date.parse(p.ends_at);
  return until > now ? { name: "ops.contacts.replan", query: { plan: p.plan.id } } : null;
}
