export type FilterKey =
  | "dashboard_id"
  | "mission_id"
  | "boundary"
  | "context_reason"
  | "replay_run_id"
  | "affected_placement_id";

export type FilterValues = Record<FilterKey, string>;

export type FilterField = {
  key: FilterKey;
  id: string;
  name: string;
  label: string;
  placeholder: string;
};

export type Summary = {
  decision_count: number;
  status_summary: string;
  refresh_summary: string;
  source_summary: string;
  selected_decision_state: "none" | "missing" | "visible" | "outside_results";
  empty_state: {
    id: string;
    copy: string;
  };
  stats: Array<{
    id: string;
    label: string;
    value: number;
  }>;
};

export type DecisionRow = {
  __dom_id: string;
  id: string;
  key: string;
  dashboard: string;
  mission: string;
  source: string;
  boundary: string;
  status: string;
  context: string;
  replay_run: string;
  refresh: string;
  artifacts: string;
  affected_count: string;
  affected_placements: string;
  affected_impact: string;
  observed: string;
  inspect_action: {
    id: string;
    href: string;
    selected: boolean;
  };
};

export type DetailFact = {
  key: string;
  label: string;
  value: string;
};

export type DetailPair = {
  key: string;
  label: string;
  value: string;
};

export type DecisionDetail = {
  id: string;
  subtitle: string;
  close_action: {
    id: string;
    href: string;
  };
  evidence: {
    id: string;
    decision_key: string;
    source: string;
    groups: Array<{
      key: string;
      label: string;
      facts: DetailFact[];
    }>;
  };
  sections: Array<{
    id: string;
    key: string;
    label: string;
    empty_copy: string;
    pairs: DetailPair[];
  }>;
};

export type DashboardRuntimeDiagnosticsProps = {
  summary: Summary;
  filters: {
    values: FilterValues;
    fields: FilterField[];
    clear_href: string;
  };
  decisions: DecisionRow[];
  selection: {
    state: "none" | "missing" | "visible" | "outside_results";
    decision_key: string | null;
    missing: boolean;
    outside_results: boolean;
    context_href: string | null;
    detail: DecisionDetail | null;
  };
  navigation: {
    admin_href: string;
  };
};
