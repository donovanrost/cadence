export const context = { missionId: "mission-1" };
export function directoryPayload() {
  return {
    navigation: {
      fallback_href: "/missions/mission-1/comms/transports",
      breadcrumbs: [{ label: "Mission", href: "/missions/mission-1" }],
    },
    data: {
      title: "Transports",
      items: [
        {
          id: "transports-1",
          display_name: "Saved Transport",
          href: "/missions/mission-1/comms/transports/transports-1",
          origin: "direct",
          transport_kind: "tcp_socket",
          direction_capability: "inbound",
          version: 3,
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
      fallback_href: "/missions/mission-1/comms/transports/transports-1",
      breadcrumbs: [{ label: "Mission", href: "/missions/mission-1" }],
    },
    data: {
      id: "transports-1",
      display_name: "Saved Transport",
      href: "/missions/mission-1/comms/transports/transports-1",
      list_href: "/missions/mission-1/comms/transports",
      version: 3,
      lifecycle_state: "active",
      origin: "direct",
      transport_kind: "tcp_socket",
      direction_capability: "inbound",
      provider_managed: false,
    },
  };
}
