import type { DirectoryData } from "./contracts";
export function spacecraftDirectoryFixture(): DirectoryData {
  const href = "/missions/mission-a/spacecraft";
  const element = { attrs: {} };
  return {
    presentation: {
      root: { attrs: { id: "spacecraft-management-page" } },
      header: {
        ...element,
        body: element,
        content: element,
        title: { ...element, text: "Spacecraft" },
        subtitle: { ...element, text: "Manage identities and profiles." },
      },
      breadcrumbs: {
        ...element,
        items: [
          { label: "Mission A", href: "/missions/mission-a" },
          { label: "Spacecraft", href },
        ],
      },
      summary_tiles: [
        {
          id: "spacecraft-tile-missing-scid",
          label: "Missing SCID",
          value: 1,
          href: `${href}?filter=missing_scid`,
          active: false,
          warning: true,
        },
      ],
      roster: {
        href,
        filter: "missing_profile",
        fleet_empty: false,
        subtitle: "2 total",
        new_spacecraft_href: `${href}/new`,
        search: "",
        sort_by: "scid",
        sort_dir: "asc",
        filtered_empty: false,
        page: 1,
        page_size: 1,
        total_count: 2,
        pagination_visible: true,
        range_label: "1–1 of 2",
        previous_page: 1,
        next_page: 2,
        previous_disabled: true,
        next_disabled: false,
        rows: [
          {
            id: "spacecraft-one",
            actions_id: "one-actions",
            display_name: "Vehicle One",
            scid_label: "42",
            scid_missing: false,
            profile_label: "Not set",
            status: "attention",
            status_label: "Attention",
            href: `${href}/one`,
            identity_href: `${href}/one/identity`,
          },
        ],
      },
      profiles: {
        empty: false,
        truncated: true,
        subtitle: "6 total",
        new_profile_href: `${href}/profiles/new`,
        all_profiles_href: `${href}/profiles`,
        rows: [
          {
            id: "profile-one",
            display_name: "Profile One",
            href: `${href}/profiles/one`,
            fleet_entries: [{ label: "v1 × 2", href: null }],
            protocols: "TM / TC",
            applications: "Telemetry Decom",
            status: "ready",
            status_label: "Current",
          },
        ],
      },
    },
  };
}
