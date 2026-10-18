export type DirectorySort = "updated" | "name" | "name_desc";
export const directorySorts: readonly DirectorySort[] = ["updated", "name", "name_desc"];

export type DirectoryFilters = {
  query: string;
  tags: string[];
  starred: boolean;
  archived: boolean;
  sort: DirectorySort;
  page: number;
};

export type DashboardRow = {
  id: string;
  name: string;
  description: string | null;
  tags: string[];
  archived: boolean;
  starred: boolean;
  version: number | null;
  updated_at: string | null;
  updated_by: string | null;
  viewed_at: string | null;
};

export type DirectoryModel = {
  version: 2;
  mission_id: string;
  author: boolean;
  filters: DirectoryFilters;
  available_tags: string[];
  total: number;
  pages: number;
  page_size: 50;
  rows: DashboardRow[];
  shortcuts: { starred: DashboardRow[]; recent: DashboardRow[] };
};

export type DirectoryPage = { model: DirectoryModel; sequence: number };

export const directoryActions = ["star", "archive", "restore", "duplicate"] as const;
export type DirectoryAction = (typeof directoryActions)[number];
export type DirectoryCommands = {
  star: { dashboard_id: string; starred: boolean };
  archive: { dashboard_id: string };
  restore: { dashboard_id: string };
  duplicate: { dashboard_id: string; name: string };
};

export type DirectoryOutcome =
  | { status: "ok"; page: DirectoryPage; result: { dashboard_id: string } }
  | { status: "invalid"; code: string; page: DirectoryPage | null }
  | { status: "forbidden" | "rejected" | "unknown"; page: DirectoryPage | null };
