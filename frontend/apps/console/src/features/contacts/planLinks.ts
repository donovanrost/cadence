import type { RouteLocationRaw } from "vue-router";

/**
 * Where a booking's contact plan and requirement open (ux U74, #676): the plan on K1 (`?plan=`,
 * with its day and revision when known, so K1 opens that day on that plan), the requirement on its
 * Setup page. D2's Booked row and the reservation record both link through these.
 */
export type PlanRef = Readonly<{
  id: string;
  version: number | null;
  day?: string | null | undefined;
}>;

export const planRoute = (p: PlanRef): RouteLocationRaw => ({
  name: "ops.contacts.plan",
  query: {
    plan: p.id,
    ...(p.day ? { day: p.day.slice(0, 10) } : {}),
    ...(p.version === null ? {} : { version: String(p.version) }),
  },
});

export const requirementRoute = (id: string): RouteLocationRaw => ({
  name: "setup.contact-planning.requirement",
  params: { requirementId: id },
});
