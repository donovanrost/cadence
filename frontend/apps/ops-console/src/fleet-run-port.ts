import { queryPresentation } from "./query-presentation";
import type { FullPageSurfaceProps } from "@cadence/plugin-sdk";
import type { FleetRunPort } from "@cadence/planning-and-contacts/fleet-planning";
const actions = { continue: "refresh-fleet-run", repair: "repair-fleet-run" } as const;
export function createFleetRunPort(
  props: FullPageSurfaceProps,
  active: () => boolean,
): FleetRunPort | undefined {
  const { context, surface, application, bridge } = props;
  if (context.scope !== "mission" || surface.surfaceId !== "fleet_planning_run") return undefined;
  function admitted() {
    if (!active()) throw new Error("The fleet run view has departed.");
  }
  return {
    context: { organization_id: context.organizationId, mission_id: context.missionId },
    async execute(action, input) {
      admitted();
      if (!Object.hasOwn(actions, action) || !surface.actions.includes(actions[action]))
        throw new Error("Undeclared fleet run action.");
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
      return queryPresentation(result, "OpsFleetPlanningRun", "run", "Unavailable fleet run view.");
    },
  };
}
