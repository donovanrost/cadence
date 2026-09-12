import type { ProfileData } from "./contracts";
export function profileFixture(): ProfileData {
  const field = (name: string, type: "text" | "number" | "select", value: string) => ({
    id: "profile-" + name,
    name: "spacecraft_type[" + name + "]",
    type,
    value,
    label: name,
    required: ["display_name", "frame_size", "downlink_protocol", "uplink_protocol"].includes(name),
  });
  const section = (name: string) => ({
    id: "section-" + name,
    title: name,
    number: "01",
    description: null,
  });
  const options = (values: string[]) => values.map((value) => ({ label: value, value }));
  return {
    page: {
      id: "spacecraft-profile-new-page",
      title: "New Spacecraft Profile",
      subtitle: "Byte interpretation",
      breadcrumbs: [],
    },
    form: {
      id: "spacecraft-profile-form",
      sections: {
        identity: section("identity"),
        protocols: section("protocols"),
        frame_parameters: section("frame_parameters"),
        applications: section("applications"),
      },
      fields: {
        display_name: field("display_name", "text", ""),
        downlink_protocol: field("downlink_protocol", "select", "tm"),
        uplink_protocol: field("uplink_protocol", "select", "tc"),
        frame_size: field("frame_size", "number", ""),
        secondary_header_length: field("secondary_header_length", "number", "0"),
        insert_zone_length: field("insert_zone_length", "number", "0"),
        truncated_primary_header: field("truncated_primary_header", "select", "false"),
        ocf_length: field("ocf_length", "select", "0"),
        applications: {
          id: "profile-applications",
          name: "spacecraft_type[applications]",
          value: {},
        },
      },
      actions: {
        submit: { id: "create-spacecraft-profile-button", label: "Create Profile" },
        cancel: {
          id: "cancel-spacecraft-profile-link",
          label: "Cancel",
          href: "/missions/mission-a/spacecraft/profiles",
        },
      },
    },
    options: {
      downlink_protocols: options(["tm", "aos", "uslp"]),
      uplink_protocols: options(["tc", "uslp"]),
      truncated_primary_headers: options(["false", "true"]),
      operational_control_fields: options(["0", "4"]),
      frame_fields: {
        secondary_header_length: ["tm"],
        insert_zone_length: ["aos"],
        truncated_primary_header: ["uslp"],
      },
    },
    applications: [
      {
        id: "app-telemetry",
        key: "telemetry_decom",
        name: "spacecraft_type[applications][telemetry_decom]",
        value: "1",
        label: "Telemetry",
        description: "Decode telemetry",
        available: true,
        availability_label: null,
      },
    ],
  };
}
