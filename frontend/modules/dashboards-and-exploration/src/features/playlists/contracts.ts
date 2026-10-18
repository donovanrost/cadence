import type { WorkspaceSnapshot } from "../../workspace";
export type Page<T> = { rows: T[]; next: string | null };
export type Query = { q: string; after: string | null };
export type Choice = { id: string; name: string; published_version: number | null };
export type Playlist = {
  id: string;
  name: string;
  description: string | null;
  count: number;
  dwell_seconds: number;
  wallboard_mode: boolean;
};
export type Directory = {
  version: 1;
  organization_id: string;
  mission_id: string;
  query: Query;
  playlists: Page<Playlist>;
  choices: Page<Choice>;
};
export type DirectoryState = { model: Directory; sequence: number; phase: "ready" | "review" };
export type Search = {
  version: 1;
  organization_id: string;
  mission_id: string;
  query: Query;
  choices: Page<Choice>;
};
export type Receipt = { id: string; name: string; count: number };
export type Presentation = {
  version: 1;
  organization_id: string;
  mission_id: string;
  playlist: Omit<Playlist, "count">;
  index: number;
  total: number;
  playing: boolean;
  loaded_at: string;
  current: { id: string; name: string | null; snapshot: WorkspaceSnapshot | null };
};
