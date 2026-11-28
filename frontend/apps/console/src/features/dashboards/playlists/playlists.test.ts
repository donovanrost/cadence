import { dashboardId as dashIdReader } from "@/api/index.ts";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { missionId as missionIdReader } from "@/api/index.ts";
import {
  DWELL,
  MAX_DASHBOARDS,
  changedPlaylist,
  playlistDeleted,
  refusedDashboards,
  updatePlaylist,
} from "./api.ts";

const current = {
  id: "pl-1",
  name: "Ops wall",
  description: null,
  dwell_seconds: 30,
  wallboard_mode: true,
  updated_at: "2026-11-14T06:10:00.123456Z",
  updated_by: { id: "u-2", name: "Ana P." },
  dashboards: [{ id: "dash-1", name: "Power", archived: false }],
};

afterEach(() => vi.unstubAllGlobals());

describe("playlists against api's D23/D24 (475cf1295)", () => {
  it("uses domain's bounds", () => {
    expect(DWELL).toEqual({ min: 5, max: 900 });
    expect(MAX_DASHBOARDS).toBe(100);
  });

  it("reads the stale save's current playlist, refused dashboards and a deleted playlist", () => {
    const conflict = {
      kind: "conflict",
      code: "version_conflict",
      message: "",
      details: { current },
    } as const;
    expect(changedPlaylist(conflict)?.updated_by?.name).toBe("Ana P.");
    expect(changedPlaylist({ ...conflict, code: "library_item_changed" })).toBeNull();

    const invalid = {
      kind: "invalid",
      code: "invalid_params",
      message: "",
      details: { dashboard_ids: "Archived.", unknown: ["dash-9"] },
    } as const;
    expect(refusedDashboards(invalid)).toEqual(["dash-9"]);
    expect(refusedDashboards({ ...invalid, details: { playlist: "Bad." } })).toEqual([]);

    expect(playlistDeleted({ kind: "not_found", code: "playlist_not_found", message: "" })).toBe(
      true,
    );
    expect(playlistDeleted({ kind: "not_found", code: "not_found", message: "" })).toBe(false);
  });

  it("sends expected_updated_at with a PATCH", async () => {
    const fetch = vi.fn();
    fetch.mockResolvedValueOnce(
      new Response(JSON.stringify({ data: { id: "pl-1" } }), {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
    );
    vi.stubGlobal("fetch", fetch);
    const body = {
      name: "Ops wall",
      description: "",
      dwell_seconds: 30,
      wallboard_mode: true,
      dashboard_ids: [dashIdReader("dash-1")],
    };
    expect(
      (await updatePlaylist(missionIdReader("m-1"), "pl-1", body, current.updated_at)).ok,
    ).toBe(true);
    const init: unknown = fetch.mock.calls[0]?.[1];
    const sent: unknown =
      init && typeof init === "object" && "body" in init ? JSON.parse(String(init.body)) : null;
    expect(sent).toMatchObject({ expected_updated_at: current.updated_at, description: null });
  });
});
