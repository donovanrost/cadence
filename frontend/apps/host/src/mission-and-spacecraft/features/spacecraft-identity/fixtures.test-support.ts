import type { IdentityData } from "./contracts";
export function identityFixture(edit = false): IdentityData {
  const prefix = edit ? "spacecraft-edit" : "spacecraft";
  const field = (name: string, value: string, type: "text" | "select" = "text") => ({
    id: `${prefix}-${name.replaceAll("_", "-")}`,
    name: `spacecraft[${name}]`,
    type,
    label: name,
    required: name === "display_name",
    value,
  });
  return {
    page: {
      id: edit ? "spacecraft-edit-page" : "spacecraft-new-page",
      heading: edit ? "Spacecraft Identity" : "New Spacecraft",
      subtitle: "Identity and pinned profile",
      breadcrumbs: [{ label: "Spacecraft", href: "/missions/mission-a/spacecraft" }],
    },
    form: {
      id: edit ? "spacecraft-edit-form" : "spacecraft-form",
      profile_version: edit ? 1 : null,
      sections: {
        identity: { id: `${prefix}-identity-section`, number: "01", title: "Identity" },
        profile: { id: `${prefix}-profile-section`, number: "02", title: "Profile" },
      },
      fields: {
        display_name: field(
          "display_name",
          edit ? "Vehicle One" : "",
        ) as IdentityData["form"]["fields"]["display_name"],
        scid: field("scid", edit ? "42" : "") as IdentityData["form"]["fields"]["scid"],
        spacecraft_type_id: field(
          "spacecraft_type_id",
          edit ? "profile-one" : "",
          "select",
        ) as IdentityData["form"]["fields"]["spacecraft_type_id"],
      },
      actions: {
        submit: {
          id: edit ? "save-spacecraft-identity-button" : "create-spacecraft-button",
          label: "Save",
        },
        cancel: {
          id: "cancel-spacecraft-link",
          label: "Cancel",
          href: "/missions/mission-a/spacecraft",
        },
      },
    },
    profile_options: {
      empty: false,
      options: [
        { label: "None", value: "", version: null },
        { label: "Profile One v1 (current pin)", value: "profile-one", version: 1 },
        { label: "Profile One v2", value: "profile-one", version: 2 },
      ],
      empty_state: {
        message: "No profiles",
        action: {
          id: "create-profile",
          label: "Create one",
          href: "/missions/mission-a/spacecraft/profiles/new",
        },
        suffix: "",
      },
    },
  };
}
