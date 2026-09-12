export type StatusTone = "ready" | "attention" | "blocked" | "info";

export type Status = {
  tone: StatusTone;
  label: string;
};

export type Breadcrumb = {
  label: string;
  href: string | null;
};

export type ReadinessPage = {
  id: string;
  title: string;
  title_suffix: string;
  subtitle: string;
  breadcrumbs: Breadcrumb[];
  status: Status;
};

export type Detail = {
  label: string;
  value: string;
};

export type Action = {
  label: string;
  href: string;
};

export type ApplicationList = {
  id: string;
  empty_state: {
    id: string;
    description: string;
  };
};

export type ReadinessPanel = {
  id: string;
  title: string;
  status: Status;
  description: string;
  details: Detail[];
  action: Action;
  application_list: ApplicationList | null;
};

export type ReadinessApplication = {
  id: string;
  application_key: string;
  display_name: string;
  status: Status;
};

export type ReadinessData = {
  page: ReadinessPage;
  panels: ReadinessPanel[];
  applications: ReadinessApplication[];
  context: import("@cadence/plugin-sdk").ReadinessContext;
  contributions: unknown[];
};
