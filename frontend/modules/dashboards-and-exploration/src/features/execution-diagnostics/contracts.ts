export const collectionIds = [
  "plan",
  "requests",
  "frames",
  "cache",
  "source_execution",
  "refresh",
  "invalidation",
] as const;
export type CollectionId = (typeof collectionIds)[number];
export type DiagnosticRow = {
  kind: CollectionId | "plan_warning";
  id: string;
  identity: string;
  title: string;
  status: string;
  details: Array<{ key: string; value: string | number | boolean | null }>;
};
export type DiagnosticCollection = {
  id: CollectionId;
  state: "ready" | "unavailable";
  source: "inspection" | "durable" | "process_local" | null;
  limited: boolean;
  rows: DiagnosticRow[];
};
export type ExecutionDiagnostics = {
  version: 2;
  organization_id: string;
  mission_id: string;
  dashboard_id: string;
  name: string;
  document_version: number;
  loaded_at: string;
  collections: DiagnosticCollection[];
};
