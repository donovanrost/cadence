export const COMMS_OVERVIEW_QUERY_ID = "cadence.comms.overview" as const;
export const COMMS_OVERVIEW_QUERY_VERSION = 1 as const;

export type StatusTone = "ready" | "attention" | "blocked" | "info";

export interface PresentationAttrs {
  attrs: Record<string, string>;
}

export interface TextPresentation extends PresentationAttrs {
  text: string;
}

export interface Status {
  tone: StatusTone;
  label: string;
}

export interface EmptyState {
  title: string;
  description: string;
}

export interface TransportEmptyState extends EmptyState {
  action_label: string;
  action_href: string;
}

export interface TransportRow {
  id: string;
  display_name: string;
  metadata: string;
  href: string;
}

export interface TransportSummary {
  id: string;
  eyebrow: string;
  count: number;
  count_label: string;
  description: string;
  status: Status;
  empty: boolean;
  empty_state: TransportEmptyState;
  rows: TransportRow[];
  manage_label: string;
  manage_href: string;
  add_label: string;
  add_href: string;
}

export interface Finding {
  id: string | null;
  title: string;
  body: string;
  action_label?: string | null;
  action_href?: string | null;
  status: Status;
}

export interface FindingGroup {
  id: string;
  title: string;
  description: string;
  findings: Finding[];
}

export interface ValidationSummary {
  id: string;
  eyebrow: string;
  title: string;
  description: string;
  status: Status;
  empty: boolean;
  empty_state: EmptyState;
  findings_id: string;
  finding_groups: FindingGroup[];
}

export interface CommsOverview {
  transport: TransportSummary;
  validation: ValidationSummary;
}

export interface CommsOverviewPresentation {
  root: PresentationAttrs;
  header: {
    attrs: Record<string, string>;
    body: PresentationAttrs;
    content: PresentationAttrs;
    eyebrow: TextPresentation;
    title: TextPresentation;
    title_suffix: TextPresentation;
  };
  overview: CommsOverview;
}

export interface CommsOverviewResponse {
  queryVersion: typeof COMMS_OVERVIEW_QUERY_VERSION;
  presentation: CommsOverviewPresentation;
}
