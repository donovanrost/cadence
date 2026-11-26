import { decoders as d, detailsOf, isError, type ApiError, type Decoded } from "@/api";
import { plural } from "@/ui";

/**
 * #499 (api; the director's ruling on #283): tightening a mission's approval to 'independent'
 * suspends the automation grants that went active on one approval, until a second person approves
 * each. The save answers 409 approval_tightening_suspends_grants with that list and its digest,
 * nothing written; saving again with the digest goes ahead, and a changed list answers 409 again.
 */
const suspendedGrant = d.object({
  id: d.token,
  mission: d.object({ id: d.token, name: d.nullable(d.string) }),
  service: d.object({ id: d.token, name: d.nullable(d.string) }),
  // The grant reader's actions (plan, repair, execute, submit, approve); shown as sent.
  allowed_actions: d.array(d.string, 20),
  valid_until: d.timestamp,
});
export type SuspendedGrant = Decoded<typeof suspendedGrant>;
const suspensions = d.object({ grants: d.array(suspendedGrant, 5000), digest: d.string });
export type Suspensions = Decoded<typeof suspensions>;

/** The grants a refused tightening would suspend; null for any other failure (or an unreadable one). */
export function suspensionsOf(error: ApiError): Suspensions | null {
  return isError(error, "approval_tightening_suspends_grants")
    ? detailsOf(error, suspensions)
    : null;
}

// Words: ca-ux, U105 "The settings save that suspends" (#507).

/** U25: a service by name, or "Unknown service identity"; never its id. */
export const grantService = (g: SuspendedGrant) => g.service.name ?? "Unknown service identity";
export const grantMission = (g: SuspendedGrant) => g.mission.name ?? "Unknown mission";

// U105's action words, as the Contact planning grants panel says them (planning/grants.ts).
const grantActions = ["plan", "repair", "execute", "submit", "approve"] as const;
type GrantAction = (typeof grantActions)[number];
const isGrantAction = (a: string): a is GrantAction => grantActions.some((x) => x === a);
const ACTION_WORDS: Readonly<Record<GrantAction, string>> = {
  plan: "plan",
  repair: "repair",
  execute: "book",
  submit: "submit",
  approve: "approve",
};
const actionsText = (g: SuspendedGrant) =>
  g.allowed_actions.map((a) => (isGrantAction(a) ? ACTION_WORDS[a] : "other")).join(", ");

const missionCount = (s: Suspensions) => new Set(s.grants.map((g) => g.mission.id)).size;

/**
 * At organization level each service is named once, with "(N missions)" when it has grants on more
 * than one (ux, #507); deduplicated by service id, so two nameless services aren't merged.
 */
function serviceNames(s: Suspensions, organizationLevel: boolean): readonly string[] {
  if (!organizationLevel) return s.grants.map(grantService);
  const byService = new Map<string, { name: string; missions: Set<string> }>();
  for (const g of s.grants) {
    const entry = byService.get(g.service.id) ?? { name: grantService(g), missions: new Set() };
    entry.missions.add(g.mission.id);
    byService.set(g.service.id, entry);
  }
  return [...byService.values()].map(({ name, missions }) =>
    missions.size > 1 ? `${name} (${plural(missions.size, "mission")})` : name,
  );
}

/** "A", "A and B", "A, B and C", "A, B, C and 2 more". */
function namesText(names: readonly string[]): string {
  const shown = names.slice(0, 3);
  const more = names.length - shown.length;
  if (more > 0) return `${shown.join(", ")} and ${more} more`;
  return shown.length > 1
    ? `${shown.slice(0, -1).join(", ")} and ${shown.at(-1)}`
    : (shown[0] ?? "");
}

/** The lead: what the save will do; at organization level, on how many missions. */
export function suspendLead(s: Suspensions, organizationLevel: boolean): string {
  const on = organizationLevel ? ` on ${plural(missionCount(s), "mission")}` : "";
  const what = `Saving this suspends ${plural(s.grants.length, "automation grant")}${on}`;
  const only = s.grants.length === 1 ? s.grants[0] : undefined;
  if (only) {
    const name = grantService(only);
    return `${what}: ${name}. Until a second org admin resumes it, ${name} can't act under it.`;
  }
  return `${what}: ${namesText(serviceNames(s, organizationLevel))}. Until a second org admin resumes each, its service can't act under it.`;
}

/** One row of Show all: "Nightly planner · plan, submit · until 12-19 06:40Z", mission first at org level. */
export const grantRow = (g: SuspendedGrant, organizationLevel: boolean, until: string) =>
  `${organizationLevel ? `${grantMission(g)} · ` : ""}${grantService(g)} · ${actionsText(g)} · until ${until}`;

export const changedLine =
  "The grants this would suspend changed, so nothing was saved. Check the list, then save again.";
export const confirmLabel = (s: Suspensions) =>
  `Save and suspend ${plural(s.grants.length, "grant")}`;
