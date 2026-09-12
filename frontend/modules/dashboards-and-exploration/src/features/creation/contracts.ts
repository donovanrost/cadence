export type CreationModel = {
  version: 1;
  mission_id: string;
  mode: "new" | "clone" | "import";
  source: null | {
    id: string;
    name: string;
    description: string | null;
    version: number;
    widget_count: number;
  };
};
export type CreationState = {
  model: CreationModel;
  sequence: number;
  phase: "editing" | "submitted";
};
