import { queryPresentation } from "./query-presentation";
import type { FullPageSurfaceProps } from "@cadence/plugin-sdk";
import type { FleetStartPort } from "@cadence/planning-and-contacts/fleet-planning";
const actions = { preview: "validate-fleet-run", create: "create-fleet-run" } as const;
export function createFleetStartPort(
  props: FullPageSurfaceProps,
  active: () => boolean,
): FleetStartPort | undefined {
  const { context, surface, application, bridge } = props;
  if (context.scope !== "mission" || surface.surfaceId !== "fleet_planning_new") return undefined;
  function admitted() {
    if (!active()) throw new Error("The fleet start view has departed.");
  }
  return {
    context: { organization_id: context.organizationId, mission_id: context.missionId },
    async execute(action, input) {
      admitted();
      if (!Object.hasOwn(actions, action) || !surface.actions.includes(actions[action]))
        throw new Error("Undeclared fleet start action.");
      const result = await bridge.execute({
        applicationKey: application.applicationKey,
        applicationVersion: application.applicationVersion,
        surfaceId: surface.surfaceId,
        surfaceVersion: surface.version,
        actionId: actions[action],
        input,
        context,
      });
      admitted();
      return result;
    },
    async refresh() {
      admitted();
      const result = await bridge.query({
        queryId: surface.dataContract.id,
        version: surface.dataContract.version,
        context,
      });
      admitted();
      return queryPresentation(
        result,
        "OpsFleetPlanningNew",
        "start",
        "Unavailable fleet start view.",
      );
    },
  };
}
