export function creationFixture() {
  const field = (key: string) => ({
    id: `mission_${key}`,
    name: `mission[${key}]`,
    type: "text" as const,
    label: key,
    required: true,
    value: "",
  });
  return {
    page: {
      id: "mission-new-page",
      heading: "New Mission",
      breadcrumbs: [{ label: "Missions", href: "/missions" }],
    },
    form: {
      id: "mission-form",
      fields: { display_name: field("display_name"), slug: field("slug") },
      actions: {
        submit: { id: "create-mission-button", label: "Create Mission" },
        cancel: { id: "cancel-mission-link", label: "Cancel", href: "/missions" },
      },
    },
  };
}
