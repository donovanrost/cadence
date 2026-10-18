import { queryPresentation } from "./query-presentation";
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
    protocol: "remote-query",
    context: { organization_id: context.organizationId, mission_id: context.missionId },
    async refresh() {
      admitted();
      const result = await bridge.query({
        queryId: surface.dataContract.id,
        version: surface.dataContract.version,
        context,
      });
      admitted();
      return queryPresentation(result, "OpsContactRecord", "record", "Unavailable contact record.");
    },
  };
}
