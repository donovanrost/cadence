export type StatusTone = "info" | "ready" | "attention" | "blocked";
export type ButtonVariant = "primary" | "secondary" | "danger";
export type LifecycleEvent = "install" | "disable" | "uninstall";

export type ApplicationEvent = {
  key: string;
};

export type Confirmation = {
  title: string;
  message: string;
  confirm_label: string;
  tone: "attention" | "danger";
  prompt: string;
};

export type LifecycleAction = {
  id: string;
  action_id: string;
  label: string;
  variant: ButtonVariant;
  effect: string;
  execution: string;
  confirmation: Confirmation | null;
};

export type StatusFact = {
  id: string;
  label: string;
  value: string | null;
};

export type ApplicationCard = {
  id: string;
  application_key: string;
  application_version: number | null;
  display_name: string;
  description: string;
  lifecycle_state: string | null;
  installable: boolean;
  manageable: boolean;
  uninstallable: boolean;
  scope_label: string;
  manage_path: string;
  status: {
    state: string;
    label: string;
    tone: StatusTone;
    facts: StatusFact[];
  };
  install_action: LifecycleAction | null;
  disable_action: LifecycleAction | null;
  uninstall_action: LifecycleAction | null;
  unavailable_message: string | null;
};

export type MissingProfile = {
  kind: "missing";
  id: string;
  label: string;
  title: string;
  description: string;
  action: {
    label: string;
    path: string;
  };
};

export type PinnedProfile = {
  kind: "pinned";
  id: string;
  label: string;
  display_name: string;
  version: number;
  status: {
    tone: "ready" | "attention";
    label: string;
  };
};

export type Profile = MissingProfile | PinnedProfile;
export type Attrs = Record<string, string>;
export type ElementPresentation = { attrs: Attrs };
export type TextPresentation = ElementPresentation & { text: string };
export type BreadcrumbItem = {
  key: string;
  separator: TextPresentation | null;
  link: TextPresentation | null;
  current: TextPresentation | null;
};
export type CompactBreadcrumb = { label: string; href: string | null };
export type Header = {
  attrs: Attrs;
  body: ElementPresentation;
  content: ElementPresentation;
  breadcrumbs: { attrs: Attrs; items: (BreadcrumbItem | CompactBreadcrumb)[] };
  title: TextPresentation;
  subtitle: TextPresentation;
};
export type MissionPresentation = {
  root: ElementPresentation;
  header: Header;
  applications_component: { attrs: Attrs; props: { applications: ApplicationCard[] } };
};
export type SpacecraftPresentation = {
  root: ElementPresentation;
  header: Header & { actions: { attrs: Attrs; readiness: TextPresentation } };
  component: ElementPresentation;
  profile: Profile;
  applications: ApplicationCard[];
};
export type InstallationSnapshot =
  | { version: 1; scope: "mission"; status: "ready"; data: MissionPresentation }
  | { version: 1; scope: "spacecraft"; status: "ready"; data: SpacecraftPresentation };
export type InstallationAction = (
  event: LifecycleEvent,
  payload: ApplicationEvent,
) => Promise<void>;
