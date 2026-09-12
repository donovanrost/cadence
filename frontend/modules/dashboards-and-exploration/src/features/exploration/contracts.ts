export type ExplorationQuery = Record<string, string>;
export type ExplorationRow = {
  key: string;
  point_id: string;
  sample_id: string | null;
  time: string | null;
  axis: "generation_time" | "receipt_time";
  value: string | number | boolean | null;
  value_kind: "number" | "string" | "enum" | "boolean";
  unit: string | null;
  source: {
    data_source_id: string | null;
    source_binding_id: string | null;
    dataset: string | null;
    realm: string;
  };
};
export type ExplorationModel = {
  version: 3;
  organization_id: string;
  mission_id: string;
  query: ExplorationQuery;
  origin:
    | { status: "ready"; dashboard: { id: string; name: string } }
    | { status: "not_provided" | "unavailable"; dashboard: null };
  loaded_at: string;
  status:
    | "ready"
    | "empty"
    | "unavailable"
    | "point_required"
    | "unsupported_exploration_source"
    | "unsupported_exploration_scope";
  effective_time: { mode: string; axis: string; from: string | null; to: string | null } | null;
  rows: ExplorationRow[];
  limited: boolean;
  warnings: { code: string; severity: "info" | "warning" | "error" }[];
  warnings_limited: boolean;
  inspection: SampleInspection;
};

export type SampleValue = {
  state: "ready" | "not_recorded" | "limited" | "unsupported";
  text: string | null;
  format: "json" | "hex" | null;
};
export type PhysicalSample = {
  point_id: string;
  point_name: string | null;
  sample_id: string;
  spacecraft_id: string | null;
  receipt_time: string;
  generation_time: string | null;
  quality: "good" | "suspect" | "bad";
  raw_value: SampleValue;
  engineering_value: SampleValue;
  source: {
    data_source_id: string;
    source_binding_id: string;
    realm: "flight" | "rehearsal" | "replay" | "simulation";
    source_endpoint_id: string | null;
    replay_run_id: string | null;
  };
  record: {
    packet_id: string | null;
    evidence_id: string | null;
    packet_definition_id: string | null;
    packet_definition_version: number | null;
    validity_state: "canonical" | "duplicate" | "conflict" | "superseded" | "advisory" | null;
  };
};
export type SampleInspection =
  | { status: "ready"; sample: PhysicalSample }
  | {
      status:
        | "not_selected"
        | "not_found"
        | "ambiguous"
        | "unsupported"
        | "timeout"
        | "unavailable";
      sample: null;
    };
