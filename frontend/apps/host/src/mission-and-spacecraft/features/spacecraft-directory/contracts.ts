export type Status = "ready" | "attention";

export type SummaryTile = {
  id: string;
  label: string;
  value: number;
  href: string;
  active: boolean;
  warning: boolean;
};

export type SpacecraftRow = {
  id: string;
  actions_id: string;
  display_name: string;
  scid_label: string;
  scid_missing: boolean;
  profile_label: string;
  status: Status;
  status_label: string;
  href: string;
  identity_href: string;
};

export type Roster = {
  href: string;
  filter: string;
  fleet_empty: boolean;
  subtitle: string;
  new_spacecraft_href: string;
  search: string;
  sort_by: "display_name" | "scid";
  sort_dir: "asc" | "desc";
  filtered_empty: boolean;
  page: number;
  page_size: number;
  total_count: number;
  pagination_visible: boolean;
  range_label: string;
  previous_page: number;
  next_page: number;
  previous_disabled: boolean;
  next_disabled: boolean;
  rows: SpacecraftRow[];
};

export type FleetEntry = {
  label: string;
  href: string | null;
};

export type ProfileRow = {
  id: string;
  display_name: string;
  href: string;
  fleet_entries: FleetEntry[];
  protocols: string;
  applications: string;
  status: Status;
  status_label: string;
};

export type Profiles = {
  empty: boolean;
  truncated: boolean;
  subtitle: string;
  new_profile_href: string;
  all_profiles_href: string;
  rows: ProfileRow[];
};

export type DirectoryData = {
  presentation: {
    root: { attrs: Record<string, string> };
    header: {
      attrs: Record<string, string>;
      body: { attrs: Record<string, string> };
      content: { attrs: Record<string, string> };
      title: { attrs: Record<string, string>; text: string };
      subtitle: { attrs: Record<string, string>; text: string };
    };
    breadcrumbs: { attrs: Record<string, string>; items: { label: string; href: string | null }[] };
    summary_tiles: SummaryTile[];
    roster: Roster;
    profiles: Profiles;
  };
};

export type NavigateDirectory = (href: string, replace?: boolean) => void;
