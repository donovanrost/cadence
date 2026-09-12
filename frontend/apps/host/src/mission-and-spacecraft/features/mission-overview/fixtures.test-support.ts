export function overviewFixture(mission = "mission-a") {
  const status = { tone: "blocked" as const, label: "Needs identity" };
  return {
    overview: {
      mission: { eyebrow: "Mission", display_name: mission, slug: mission },
      readiness_cards: [
        { title: "Need SCID", value: 1, status, description: "Set spacecraft identity." },
      ],
      setup: {
        eyebrow: "Readiness",
        title: "Spacecraft readiness",
        description: "",
        issue_count: 1,
        status,
        empty: false,
        empty_state: {
          title: "No spacecraft",
          action_label: "Add spacecraft",
          action_href: `/missions/${mission}/spacecraft/new`,
        },
      },
    },
    spacecraft_readiness: [
      {
        id: "sc-one",
        __dom_id: "spacecraft-readiness-sc-one",
        actions_id: "sc-one-readiness-actions",
        spacecraft_display_name: "SC One",
        spacecraft_id: "sc-one",
        scid_label: "Not set",
        endpoint_label: "Missing",
        endpoint_ref_label: "Not created",
        path_label: "No downlink route",
        path_detail: "Not configured",
        status: "blocked" as const,
        status_label: "Needs identity",
        issue: "Set SCID",
        primary_action: "Set SCID",
        primary_action_href: `/missions/${mission}/spacecraft/sc-one/readiness`,
        view_spacecraft_href: `/missions/${mission}/spacecraft/sc-one`,
      },
    ],
  };
}
