type Attrs = Record<string, string>;
type ElementPresentation = { attrs: Attrs };
type PageHeaderPresentation = ElementPresentation & {
  body: ElementPresentation;
  content: ElementPresentation;
  title: ElementPresentation & { text: string };
  subtitle: ElementPresentation & { text: string };
};
type PageHeaderAction = { id: string; label: string; href: string };

export type SpacecraftProfileRow = {
  id: string;
  display_name: string;
  version: string;
  downlink_protocol: string;
  uplink_protocol: string;
  applications: string;
  href: string;
};

export type ProfileDirectory = {
  root: ElementPresentation;
  header: PageHeaderPresentation & {
    actions: ElementPresentation & {
      new_profile: PageHeaderAction;
    };
  };
  empty_state: { title: string; description: string } | null;
  card: {
    attrs: Attrs;
    body: ElementPresentation;
    list_component: ElementPresentation;
    rows: SpacecraftProfileRow[];
  } | null;
};

export type Navigation = { breadcrumbs: { label: string; href: string | null }[] };

export type DetailItem = {
  id: string;
  label: string;
  value: string;
};

export type Application = {
  id: string;
  label: string;
};

export type SpacecraftProfile = {
  id: string;
  profile_id: string;
  display_name: string;
  version: string;
  lifecycle: string;
  downlink_protocol: string;
  uplink_protocol: string;
  packet_protocol: string;
  frame_parameters: DetailItem[];
  applications: Application[];
};

export type Labels = {
  byte_interpretation: string;
  applications: string;
  version_history: string;
  frame_parameters: string;
  no_applications: string;
  downlink_protocol: string;
  uplink_protocol: string;
  packet_protocol: string;
  lifecycle: string;
  version: string;
  downlink: string;
  uplink: string;
};

export type Version = {
  id: string;
  version: string;
  lifecycle: string;
  downlink_protocol: string;
  uplink_protocol: string;
};

export type ProfileDetail = {
  profile: SpacecraftProfile;
  navigation: Navigation;
  labels: Labels;
  versions: Version[];
};
