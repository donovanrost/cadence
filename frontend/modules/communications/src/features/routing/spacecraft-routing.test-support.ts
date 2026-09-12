export const spacecraftRoutingContext = {
  organizationId: "org-1",
  missionId: "mission-1",
  spacecraftId: "spacecraft-1",
};
export function spacecraftRoutingFixture(empty = false) {
  return {
    page: {
      title: "Comms Routing",
      subtitle: "Durable routing rules for this spacecraft.",
      breadcrumbs: [
        { label: "Mission", href: "/missions/mission-1" },
        { label: "Spacecraft", href: "/missions/mission-1/spacecraft" },
        { label: "Nova-1", href: "/missions/mission-1/spacecraft/spacecraft-1" },
        { label: "Routing", href: null },
      ],
      new_rule: {
        id: "new-spacecraft-routing-rule-link",
        label: "New Routing Rule",
        href: "/missions/mission-1/comms/routing/new?spacecraft_id=spacecraft-1",
      },
      empty_state: {
        title: "No routing rules",
        description: "Create a routing rule to use a mission transport.",
      },
      rules_id: "spacecraft-routing-rules",
      rows: empty
        ? []
        : [
            {
              id: "spacecraft-routing-rule-rule-1",
              purpose_label: "Telemetry",
              display_name: "Primary downlink",
              direction: "INBOUND",
              transport_name: "Flight TCP",
              transport_version: 1,
              role: "PRIMARY",
              state: "ENABLED",
              href: "/missions/mission-1/comms/routing/rule-1",
            },
          ],
    },
  };
}
export function spacecraftRoutingSnapshot() {
  return {
    id: "comms.spacecraft-routing",
    slot: "spacecraft.page",
    version: 1,
    status: "ready",
    context: spacecraftRoutingContext,
    data: spacecraftRoutingFixture(),
  };
}
