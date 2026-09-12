export type Page = {
  mission_id: string;
  mode: "reader" | "registration" | "settings";
  data_source_id: string | null;
};
