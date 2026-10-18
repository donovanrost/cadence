export type Breadcrumb = {
  label: string;
  href: string | null;
};

export type NewRule = {
  id: string;
  label: string;
  href: string;
};

export type EmptyState = {
  title: string;
  description: string;
};

export type RoutingRuleRow = {
  id: string;
  purpose_label: string;
  display_name: string;
  direction: string;
  transport_name: string;
  transport_version?: number;
  role: string;
  state: "ENABLED" | "DISABLED";
  href: string;
};

export type Page = {
  title: string;
  subtitle: string;
  breadcrumbs: Breadcrumb[];
  new_rule: NewRule;
  empty_state: EmptyState;
  rules_id: string;
  rows: RoutingRuleRow[];
};
