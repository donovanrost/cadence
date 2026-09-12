export const context = { missionId: "mission-1" };
export function directoryPayload() {
  return {
    navigation: {
      fallback_href: "/missions/mission-1/comms/ground-stations",
      breadcrumbs: [{ label: "Mission", href: "/missions/mission-1" }],
    },
    data: {
      title: "Ground stations",
      items: [
        {
          id: "ground-stations-1",
          display_name: "Saved GroundStation",
          href: "/missions/mission-1/comms/ground-stations/ground-stations-1",
          provider: "DSN",
          region: "Goldstone",
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
      fallback_href: "/missions/mission-1/comms/ground-stations/ground-stations-1",
      breadcrumbs: [{ label: "Mission", href: "/missions/mission-1" }],
    },
    data: {
      id: "ground-stations-1",
      display_name: "Saved GroundStation",
      href: "/missions/mission-1/comms/ground-stations/ground-stations-1",
      list_href: "/missions/mission-1/comms/ground-stations",
      lifecycle_state: "active",
      provider: "DSN",
      region: "Goldstone",
      edit_href: "/missions/mission-1/comms/ground-stations/ground-stations-1/edit",
    },
  };
}
