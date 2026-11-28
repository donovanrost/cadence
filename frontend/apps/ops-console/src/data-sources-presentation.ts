// The federated data-sources surfaces hand off to the canonical source workspace.
export type DataSourcesPresentation = {
  mission_id: string;
  mode: "reader" | "registration" | "settings";
  data_source_id: string | null;
};
