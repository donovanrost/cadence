export type DirectoryFilters = {
  query: string;
  lifecycle: "active" | "archived" | "all";
  tag: string;
  sort: "updated" | "name" | "widgets";
  page: number;
};
export type DashboardRow = {
  id: string;
  name: string;
  description: string | null;
  tags: string[];
  lifecycle: "active" | "archived";
  starred: boolean;
  version: number;
  published_version: number | null;
  widget_count: number;
};
export type DirectoryModel = {
  version: 1;
  mission_id: string;
  author: boolean;
  filters: DirectoryFilters;
  available_tags: string[];
  total: number;
  pages: number;
  page_size: 50;
  rows: DashboardRow[];
};
export type DirectoryState = {
  model: DirectoryModel;
  sequence: number;
  phase: "editing" | "submitted";
};
