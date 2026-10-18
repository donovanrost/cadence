export function directoryFixture() {
  const label = (text = "") => ({ class: "", text });
  const action = {
    attrs: { href: "/missions/new" },
    class: "",
    icon_class: "",
    label: "New Mission",
  };
  return {
    presentation: {
      root_class: "",
      header: {
        class: "",
        content_class: "",
        eyebrow: label("Organization"),
        title: { ...label("Missions"), suffix: label("1 configured") },
        actions_class: "",
        action,
      },
      empty_state: {
        visible: false,
        id: "mission-list-empty-state",
        class: "",
        icon_class: "",
        title: label(),
        description: label(),
        action_container_class: "",
        action,
      },
      card: {
        visible: true,
        class: "",
        body_class: "",
        rows: [
          {
            id: "mission-row-mission-a",
            display_name: "Mission A",
            slug: "mission-a",
            spacecraft_count: 0,
            status: "info" as const,
            status_label: "No spacecraft",
            href: "/missions/mission-a",
          },
        ],
      },
    },
  };
}
