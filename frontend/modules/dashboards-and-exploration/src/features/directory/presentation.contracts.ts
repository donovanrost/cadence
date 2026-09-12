export type LinkAction = {
  id: string;
  label: string;
  icon: string;
  href: string;
};

export type HeaderAction = LinkAction & {
  icon_class: string;
  class: string;
};

export type Page = {
  id: string;
  header: {
    eyebrow: string;
    heading: string;
    copy: string;
    count: {
      id: string;
      value: number;
      suffix: string;
    };
    author_actions: HeaderAction[];
  };
  list: {
    id: string;
    empty: {
      id: string;
      icon: string;
      heading: string;
      copy: string;
    };
  };
};

export type Option = {
  label: string;
  value: string;
};

export type SelectField = {
  id: string;
  name: string;
  type: "select";
  label: string;
  options: Option[];
};

export type FilterValues = {
  query: string;
  lifecycle: string;
  tag: string;
  sort: string;
};

export type Filters = {
  id: string;
  values: FilterValues;
  fields: {
    query: {
      id: string;
      name: string;
      type: "search";
      label: string;
      placeholder: string;
      debounce_ms: number;
    };
    lifecycle: SelectField;
    tag: SelectField;
    sort: SelectField;
  };
};

export type StarPayload = {
  "dashboard-id": string;
  starred: string;
};

export type RestorePayload = {
  "dashboard-id": string;
  "expected-version": string;
};

export type DirectoryRow = {
  id: string;
  __dom_id: string;
  dashboard_id: string;
  name: string;
  description: string | null;
  tags: string[];
  lifecycle: {
    state: "active" | "archived";
    class: string;
  };
  starred: boolean;
  open: {
    id: string;
    href: string;
  } | null;
  star: {
    id: string;
    payload: StarPayload;
    aria_label: string;
    aria_pressed: "true" | "false";
    disabled: boolean;
    title: string | null;
    icon: string;
  };
  widget_version_label: string;
  clone?: LinkAction;
  restore: {
    id: string;
    label: string;
    icon: string;
    payload: RestorePayload;
    disabled: boolean;
    lifecycle_action: string;
    action_available: string;
  } | null;
};

export type DirectoryPresentationProps = {
  page: Page;
  filters: Filters;
  dashboard_directory: DirectoryRow[];
};
