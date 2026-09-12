import type { FullPageSurfaceProps } from "@cadence/plugin-sdk";
import type { ReservationPort } from "@cadence/planning-and-contacts/contact-scheduling";
const actions = [
  "approve-provider-change",
  "reject-provider-change",
  "acknowledge-provider-change",
];
export function createReservationPort(
  props: FullPageSurfaceProps,
  active: () => boolean,
): ReservationPort | undefined {
  const { context, surface, application, bridge } = props;
  if (context.scope !== "mission" || surface.surfaceId !== "contact_detail") return undefined;
  function admitted() {
    if (!active()) throw new Error("The reservation review has departed.");
  }
  return {
    context: { organization_id: context.organizationId, mission_id: context.missionId },
    async execute(action, input) {
      admitted();
      if (!actions.includes(action) || !surface.actions.includes(action))
        throw new Error("Undeclared reservation action.");
      const result = await bridge.execute({
        applicationKey: application.applicationKey,
        applicationVersion: application.applicationVersion,
        surfaceId: surface.surfaceId,
        surfaceVersion: surface.version,
        actionId: action,
        input,
        context,
      });
      admitted();
      return result;
    },
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
        candidate?.presentation?.component !== "OpsContactDetail"
      )
        throw new Error("Unavailable reservation review.");
      return candidate.presentation.props?.detail;
    },
  };
}
