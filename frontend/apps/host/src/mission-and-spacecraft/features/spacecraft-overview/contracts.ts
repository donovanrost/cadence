export type StatusTone = "ready" | "attention" | "blocked" | "info";

export type Status = {
  tone: StatusTone;
  label: string;
};

export type NavigationItem = {
  label: string;
  href: string | null;
};

export type NavigationLink = {
  label: string;
  href: string;
};

export type Page = {
  id: string;
  header: {
    title: string;
    breadcrumbs: NavigationItem[];
    title_suffix: {
      set: boolean;
      label: string;
    };
  };
};

export type ProfileBinding = {
  id: string;
  eyebrow: string;
  bound: boolean;
  title: string;
  description: string | null;
  version: string | null;
  protocols: Array<{
    label: string;
    value: string;
  }>;
  status: Status;
  view_profile_href: string | null;
  profile_action: NavigationLink;
};

export type ApplicationRow = {
  id: string;
  application_key: string;
  display_name: string;
  status: Status;
  manage_href: string | null;
};

export type ApplicationInventory = {
  id: string;
  list_id: string;
  visible: boolean;
  title: string;
  description: string;
  empty: boolean;
  empty_state: string;
  rows: ApplicationRow[];
  view_action: NavigationLink;
};

export type WorkflowCard = {
  id: string;
  title: string;
  value: string;
  description: string;
  status: Status;
  action: NavigationLink;
};

export type DetailValue = {
  label: string;
  value: string;
};

export type Overview = {
  title: string;
  scid: DetailValue;
  display_name: DetailValue;
  spacecraft_id: DetailValue;
  mission: DetailValue & { href: string };
  organization_id: DetailValue;
  metadata_json: string | null;
};

export type OverviewData = {
  page: Page;
  profile_binding: ProfileBinding;
  applications: ApplicationInventory;
  workflow_cards: WorkflowCard[];
  overview: Overview;
};
