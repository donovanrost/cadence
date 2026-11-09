import { plural } from "@/ui";
import type { PlanDetail } from "./api.ts";

/**
 * Plan coverage in ux U23 units: spacecraft is the headline unit, contacts short the secondary
 * figure, and a gap is one unmet requirement. Every count names its unit.
 */
export function coverage(plan: Pick<PlanDetail, "demand" | "unmet">) {
  const uncovered = plan.demand.spacecraft.filter((s) => !s.rule_met);
  const contactsShort = uncovered.reduce(
    (sum, s) => sum + Math.max(0, (s.contacts.need ?? 0) - s.contacts.have),
    0,
  );
  return { spacecraft: uncovered.length, contactsShort, gaps: plan.unmet.length };
}

/** `10 spacecraft not covered` */
export const spacecraftNotCovered = (n: number) =>
  `${plural(n, "spacecraft", "spacecraft")} not covered`;
/** `40 contacts short` */
export const contactsShortText = (n: number) => `${plural(n, "contact")} short`;
