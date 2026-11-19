import { paramText } from "./route-params.ts";
import { computed, type ComputedRef } from "vue";
import { useRoute } from "vue-router";
import type { SessionMission, SessionOrganization } from "@/api/session.ts";
import { useSession } from "./session.ts";

export type ConsoleScope =
  | { kind: "none" }
  | { kind: "unknown-organization"; slug: string }
  | { kind: "organization"; organization: SessionOrganization }
  | { kind: "unknown-mission"; organization: SessionOrganization; slug: string }
  | { kind: "mission"; organization: SessionOrganization; mission: SessionMission };

export type MissionScope = Extract<ConsoleScope, { kind: "mission" }>;

const param = (value: unknown): string | null =>
  typeof value === "string" && value ? value : null;

/** The org/mission named by the current URL, resolved against the session. Derived, never copied. */
export function useConsoleScope(): ComputedRef<ConsoleScope> {
  const route = useRoute();
  const session = useSession();
  return computed(() => {
    const orgSlug = param(paramText(route.params, "org"));
    if (orgSlug === null) return { kind: "none" };
    const organization = session.organizations.find((org) => org.slug === orgSlug);
    if (!organization) return { kind: "unknown-organization", slug: orgSlug };
    const missionSlug = param(paramText(route.params, "mission"));
    if (missionSlug === null) return { kind: "organization", organization };
    const mission = organization.missions.find((m) => m.slug === missionSlug);
    if (!mission) return { kind: "unknown-mission", organization, slug: missionSlug };
    return { kind: "mission", organization, mission };
  });
}

/**
 * For screens under /:org/:mission. The shell renders those screens only when the scope
 * resolved, so this throws if used elsewhere.
 */
export function useMissionScope(): ComputedRef<MissionScope> {
  const scope = useConsoleScope();
  return computed(() => {
    const value = scope.value;
    if (value.kind !== "mission") throw new Error("useMissionScope() used outside a mission route");
    return value;
  });
}
