export type LibraryItem = { id: string; name: string; description: string; latest_version: number };
export type DashboardTarget = { id: string; name: string; version: number | null };
export type LibraryQuery = {
  q: string;
  after: string | null;
  item_id: string | null;
  version: number | null;
  before_version: number | null;
  consumer_after: string | null;
  dashboard_query: string;
  dashboard_after: string | null;
  target_id: string | null;
};
export type LibraryModel = {
  version: 1;
  organization_id: string;
  mission_id: string;
  query: LibraryQuery;
  items: LibraryItem[];
  next_item: string | null;
  selected: null | {
    item: LibraryItem;
    version: number;
    widget_json: string;
    versions: {
      version: number;
      summary: string;
      actor_id: string | null;
      saved_at: string | null;
    }[];
    next_version: number | null;
    consumers: {
      total: number;
      next: string | null;
      rows: (DashboardTarget & { pins: { id: string; version: number }[] })[];
    };
  };
  dashboards: DashboardTarget[];
  next_dashboard: string | null;
  target: (DashboardTarget & { version: number }) | null;
};
export type LibraryState = { sequence: number; phase: "ready" | "review"; model: LibraryModel };
export const libraryActions = [
  "create_item",
  "add_version",
  "add_to_draft",
  "reload_library",
] as const;
export type LibraryAction = (typeof libraryActions)[number];
export type LibraryReceipt = {
  version: 1;
  event: Exclude<LibraryAction, "reload_library">;
  item_id: string;
  library_version: number;
  dashboard_id: string | null;
  document_version: number | null;
  placement_id: string | null;
};
