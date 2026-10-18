import type { OverviewData } from "./contracts";

export function overviewFixture(): OverviewData {
  const base = "/missions/mission-a/spacecraft/craft-a";
  return {
    page: {
      id: "spacecraft-show-page",
      header: {
        title: "Nova",
        breadcrumbs: [{ label: "Spacecraft", href: "/missions/mission-a/spacecraft" }],
        title_suffix: { set: true, label: "SCID 0" },
      },
    },
    profile_binding: {
      id: "spacecraft-profile-binding",
      eyebrow: "Pinned Profile",
      bound: true,
      title: "Flight Profile",
      description: null,
      version: "v1",
      protocols: [{ label: "Downlink", value: "TM" }],
      status: { tone: "ready", label: "Pinned" },
      view_profile_href: "/missions/mission-a/spacecraft/profiles/profile-a",
      profile_action: { label: "Change profile", href: base + "/identity" },
    },
    applications: {
      id: "spacecraft-applications",
      list_id: "spacecraft-applications-list",
      visible: true,
      title: "Applications",
      description: "Profile-declared applications.",
      empty: true,
      empty_state: "No applications are declared.",
      rows: [],
      view_action: { label: "View applications", href: base + "/applications" },
    },
    workflow_cards: [
      {
        id: "spacecraft-workflow-readiness",
        title: "Readiness",
        value: "Profile bound",
        description: "Review setup before commanding.",
        status: { tone: "info", label: "Review setup" },
        action: { label: "Review readiness", href: base + "/readiness" },
      },
    ],
    overview: {
      title: "Overview",
      scid: { label: "SCID", value: "0" },
      display_name: { label: "Display Name", value: "Nova" },
      spacecraft_id: { label: "Spacecraft ID", value: "craft-a" },
      mission: { label: "Mission", value: "Mission A", href: "/missions/mission-a" },
      organization_id: { label: "Organization ID", value: "org-a" },
      metadata_json: null,
    },
  };
}
