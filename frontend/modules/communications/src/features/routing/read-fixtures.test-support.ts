export const context = { missionId: "mission-1" };
export function directoryPayload() {
  return {
    navigation: {
      fallback_href: "/missions/mission-1/comms/routing",
      breadcrumbs: [{ label: "Mission", href: "/missions/mission-1" }],
    },
    data: {
      title: "Routing",
      items: [
        {
          id: "routing-1",
          display_name: "Saved Routing",
          href: "/missions/mission-1/comms/routing/routing-1",
          spacecraft_id: "spacecraft-1",
          spacecraft_name: "Firebird",
          purpose_label: "Telemetry",
          direction: "inbound",
          transport_id: "transport-1",
          transport_name: "Lab TCP",
          role: "primary",
          enabled: true,
        },
      ],
      total_count: 2,
      page: 1,
      page_count: 2,
      page_size: 1,
      query: "Saved",
      sort: "display_name",
      dir: "asc",
    },
  };
}
export function detailPayload() {
  return {
    navigation: {
      fallback_href: "/missions/mission-1/comms/routing/routing-1",
      breadcrumbs: [{ label: "Mission", href: "/missions/mission-1" }],
    },
    data: {
      id: "routing-1",
      display_name: "Saved Routing",
      href: "/missions/mission-1/comms/routing/routing-1",
      list_href: "/missions/mission-1/comms/routing",
      enabled: true,
      lifecycle_state: "active",
      spacecraft_id: "spacecraft-1",
      spacecraft_name: "Firebird",
      purpose_label: "Telemetry",
      direction: "inbound",
      transport_id: "transport-1",
      transport_name: "Lab TCP",
      transport_version: 3,
      role: "primary",
    },
  };
}
