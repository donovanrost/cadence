import type { Scid } from "@/api/ids.ts";
import type { Raw, RawOpt, InMission, SpacecraftTab } from "./route-types.ts";

/** Ops-mode routes (inside a mission). Part of ConsoleRoutes (route-map.ts). */
export interface OpsRoutes {
  "ops.now": InMission<"ops.now", "/now">;
  "ops.fleet": InMission<"ops.fleet", "/fleet">;
  "ops.spacecraft": InMission<
    "ops.spacecraft",
    "/fleet/:scId(\\d+)/:tab?",
    // The SCID, a number (scidParam reads it back); never the spacecraft id (§12C, audit §1.2).
    { scId: Scid; tab?: SpacecraftTab | null | undefined },
    { scId: string; tab?: SpacecraftTab | "" }
  >;
  "ops.alarms": InMission<"ops.alarms", "/alarms">;
  "ops.commands": InMission<"ops.commands", "/commands">;
  "ops.commands.new": InMission<"ops.commands.new", "/commands/new">;
  "ops.commands.request": InMission<
    "ops.commands.request",
    "/commands/:requestId/:view?",
    { requestId: Raw; view?: "review" | "uplink" | null | undefined },
    { requestId: string; view?: "review" | "uplink" | "" }
  >;
  "ops.contacts": InMission<"ops.contacts", "/contacts">;
  "ops.contacts.plan": InMission<"ops.contacts.plan", "/contacts/plan">;
  "ops.contacts.replan.station": InMission<
    "ops.contacts.replan.station",
    "/contacts/replan/:stationId",
    { stationId: Raw },
    { stationId: string }
  >;
  "ops.contacts.replan": InMission<"ops.contacts.replan", "/contacts/replan">;
  "ops.contacts.review": InMission<"ops.contacts.review", "/contacts/review">;
  "ops.contacts.history": InMission<"ops.contacts.history", "/contacts/history">;
  "ops.contact": InMission<
    "ops.contact",
    "/contacts/:contactId",
    { contactId: Raw },
    { contactId: string }
  >;
  "ops.telemetry": InMission<"ops.telemetry", "/telemetry">;
  "ops.dashboards": InMission<"ops.dashboards", "/telemetry/dashboards">;
  "ops.dashboards.new": InMission<"ops.dashboards.new", "/telemetry/dashboards/new">;
  "ops.dashboards.library": InMission<"ops.dashboards.library", "/telemetry/dashboards/library">;
  "ops.dashboards.library.item": InMission<
    "ops.dashboards.library.item",
    "/telemetry/dashboards/library/:itemId",
    { itemId: Raw },
    { itemId: string }
  >;
  "ops.dashboards.playlists": InMission<
    "ops.dashboards.playlists",
    "/telemetry/dashboards/playlists"
  >;
  "ops.dashboards.present": InMission<
    "ops.dashboards.present",
    "/telemetry/dashboards/playlists/:playlistId/present",
    { playlistId: Raw },
    { playlistId: string }
  >;
  "ops.dashboards.share": InMission<
    "ops.dashboards.share",
    "/telemetry/dashboards/shares/:shareId",
    { shareId: Raw },
    { shareId: string }
  >;
  "ops.dashboards.snapshot": InMission<
    "ops.dashboards.snapshot",
    "/telemetry/dashboards/snapshots/:snapshotId",
    { snapshotId: Raw },
    { snapshotId: string }
  >;
  "ops.dashboard": InMission<
    "ops.dashboard",
    "/telemetry/dashboards/:dashboardId",
    { dashboardId: Raw },
    { dashboardId: string }
  >;
  "ops.dashboard.edit": InMission<
    "ops.dashboard.edit",
    "/telemetry/dashboards/:dashboardId/edit",
    { dashboardId: Raw },
    { dashboardId: string }
  >;
  "ops.dashboard.settings": InMission<
    "ops.dashboard.settings",
    "/telemetry/dashboards/:dashboardId/settings/:tab?",
    { dashboardId: Raw; tab?: RawOpt },
    { dashboardId: string; tab?: string }
  >;
  "ops.timeline": InMission<"ops.timeline", "/timeline">;
}
