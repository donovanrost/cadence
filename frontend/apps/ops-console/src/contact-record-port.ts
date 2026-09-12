import type { FullPageSurfaceProps } from "@cadence/plugin-sdk";
import type { ContactRecordPort } from "@cadence/planning-and-contacts/contact-scheduling";
export function createContactRecordPort(
  props: FullPageSurfaceProps,
  active: () => boolean,
): ContactRecordPort | undefined {
  const { context, surface, bridge } = props;
  if (context.scope !== "mission" || surface.surfaceId !== "contact_record") return undefined;
  function admitted() {
    if (!active()) throw new Error("The contact record has departed.");
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
        candidate?.presentation?.component !== "OpsContactRecord"
      )
        throw new Error("Unavailable contact record.");
      return candidate.presentation.props?.record;
    },
  };
}
