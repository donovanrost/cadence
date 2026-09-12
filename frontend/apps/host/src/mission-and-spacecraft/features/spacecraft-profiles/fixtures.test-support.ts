import type { ProfileDetail } from "./contracts";
export function profileDetailFixture(): ProfileDetail {
  return {
    profile: {
      id: "profile-one",
      profile_id: "one",
      display_name: "Profile One",
      version: "v2",
      lifecycle: "active",
      downlink_protocol: "TM",
      uplink_protocol: "TC",
      packet_protocol: "space_packet",
      frame_parameters: [{ id: "frame-length", label: "Frame Length", value: "1024" }],
      applications: [{ id: "decom", label: "Telemetry Decom" }],
    },
    navigation: {
      breadcrumbs: [
        { label: "Mission A", href: "/missions/mission-a" },
        { label: "Spacecraft", href: "/missions/mission-a/spacecraft" },
        { label: "Profiles", href: "/missions/mission-a/spacecraft/profiles" },
        { label: "Profile One", href: null },
      ],
    },
    labels: {
      byte_interpretation: "Byte Interpretation",
      applications: "Applications",
      version_history: "Version History",
      frame_parameters: "Frame Parameters",
      no_applications: "No applications declared.",
      downlink_protocol: "Downlink Protocol",
      uplink_protocol: "Uplink Protocol",
      packet_protocol: "Packet Protocol",
      lifecycle: "Lifecycle",
      version: "Version",
      downlink: "Downlink",
      uplink: "Uplink",
    },
    versions: [1, 2].map((version) => ({
      id: `version-${version}`,
      version: `v${version}`,
      lifecycle: "active",
      downlink_protocol: "TM",
      uplink_protocol: "TC",
    })),
  };
}
