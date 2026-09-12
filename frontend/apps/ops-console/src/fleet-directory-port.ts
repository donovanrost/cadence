import type { FullPageSurfaceProps } from "@cadence/plugin-sdk";
import type { FleetDirectoryPort } from "@cadence/planning-and-contacts/fleet-planning";
export function createFleetDirectoryPort(
  props: FullPageSurfaceProps,
  active: () => boolean,
): FleetDirectoryPort | undefined {
  const { context, surface, bridge } = props;
  if (context.scope !== "mission" || surface.surfaceId !== "fleet_planning") return undefined;
  function admitted() {
    if (!active()) throw new Error("The fleet directory has departed.");
  }
  return {
    context: { organization_id: context.organizationId, mission_id: context.missionId },
    async refresh() {
      admitted();
      const result: any = await bridge.query({
        queryId: surface.dataContract.id,
        version: surface.dataContract.version,
        context,
      });
      admitted();
      const candidate = result?.trusted_surface ?? result;
      if (
        candidate?.queryVersion !== 1 ||
        candidate?.presentation?.component !== "OpsFleetPlanning"
      )
        throw new Error("Unavailable fleet directory.");
      return candidate.presentation.props?.directory;
    },
  };
}
