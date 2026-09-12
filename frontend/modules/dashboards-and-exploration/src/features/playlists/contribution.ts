import type { Component } from "vue";
import type { OpsPageContribution } from "@cadence/plugin-sdk/ops-pages";
import PlaylistDirectory from "./PlaylistDirectory.vue";
import PlaylistPresentation from "./PlaylistPresentation.vue";
import { readState, readPresentation } from "./validation";
export const playlistsContribution = {
  id: "dashboards.playlists",
  slot: "ops.page",
  version: 1,
  title: "Dashboard playlists",
  // oxlint-disable-next-line typescript/no-unsafe-assignment -- vue-tsc checks the SFC constructor at this registration or render boundary.
  component: PlaylistDirectory,
  actions: ["create_playlist", "reload_playlists", "search_dashboards"],
  read(value, context) {
    return { state: readState(value, context), context };
  },
} as const satisfies OpsPageContribution<Component>;
export const playlistPresentationContribution = {
  id: "dashboards.playlist-present",
  slot: "ops.page",
  version: 1,
  title: "Dashboard playlist",
  // oxlint-disable-next-line typescript/no-unsafe-assignment -- vue-tsc checks the SFC constructor at this registration or render boundary.
  component: PlaylistPresentation,
  actions: [],
  read(value, context) {
    return { model: readPresentation(value, context), context };
  },
} as const satisfies OpsPageContribution<Component>;
