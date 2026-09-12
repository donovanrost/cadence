import { queryPresentation } from "./query-presentation";
import type { FullPageSurfaceProps } from "@cadence/plugin-sdk";
import type { ContactSchedulePort } from "@cadence/planning-and-contacts/contact-scheduling";
const actions = ["search", "reserve", "cancel"];
export function createContactSchedulePort(
  props: FullPageSurfaceProps,
  active: () => boolean,
): Extract<ContactSchedulePort, { protocol: "remote-query" }> | undefined {
  const { context, surface, application, bridge } = props;
  if (context.scope !== "mission" || surface.surfaceId !== "contact_schedule") return undefined;
  function admitted() {
    if (!active()) throw new Error("The contact scheduling view has departed.");
  }
  return {
    protocol: "remote-query",
    context: { organization_id: context.organizationId, mission_id: context.missionId },
    async execute(action, input) {
      admitted();
      if (!actions.includes(action) || !surface.actions.includes(action))
        throw new Error("Undeclared contact scheduling action.");
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
      const result = await bridge.query({
        queryId: surface.dataContract.id,
        version: surface.dataContract.version,
        context,
      });
      admitted();
      return queryPresentation(
        result,
        "OpsContactSchedule",
        "schedule",
        "Unavailable contact scheduling view.",
      );
    },
  };
}
