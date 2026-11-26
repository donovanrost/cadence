import { plural } from "@/ui";
import type { PlanDetail } from "./api.ts";

/**
 * Plan coverage in ux U23 units: spacecraft is the headline unit, contacts short the secondary
 * figure, and a **gap is one uncovered spacecraft** (U23 amended): its unmet requirements are
 * acknowledged together. Every count names its unit. Counted by the server (#793), never over the
 * per-spacecraft rows.
 */
export function coverage(plan: Readonly<{ demand: Pick<PlanDetail["demand"], "coverage"> }>) {
  const c = plan.demand.coverage;
  return { spacecraft: c.spacecraft_uncovered, contactsShort: c.contacts_short, gaps: c.gaps };
}

/** `10 spacecraft not covered` */
export const spacecraftNotCovered = (n: number) =>
  `${plural(n, "spacecraft", "spacecraft")} not covered`;
/** `40 contacts short` */
export const contactsShortText = (n: number) => `${plural(n, "contact")} short`;

export type GapGroup = Readonly<{ spacecraftId: string | null; unmet: PlanDetail["unmet"] }>;

/** Unmet requirements grouped per spacecraft, in first-seen order (one gap each). */
export function gapGroups(unmet: PlanDetail["unmet"]): GapGroup[] {
  const groups = new Map<string, PlanDetail["unmet"][number][]>();
  for (const u of unmet) {
    const key = u.spacecraft_id ?? "";
    groups.set(key, [...(groups.get(key) ?? []), u]);
  }
  return [...groups.entries()].map(([key, list]) => ({
    spacecraftId: key === "" ? null : key,
    unmet: list,
  }));
}
