import { describe, expect, it } from "vite-plus/test";
import { missionId as missionIdReader, decode } from "@/api";
import { settingsReader } from "./api.ts";
import { settingsWire } from "./fixtures.test-support.ts";
import {
  activityText,
  cacheText,
  parseTags,
  settingsTabs,
  shareStateText,
  snapshotWindow,
  visibilityWord,
  warningText,
  worstFirst,
} from "./present.ts";

describe("dashboard settings (slice 5, proposed D14)", () => {
  it("reads the settings with either data-visibility word", () => {
    const r = decode(settingsReader, settingsWire);
    if (!r.ok) throw r.error;
    const share = r.value.shares.rows[0];
    if (!share) throw new Error("fixture");
    expect(visibilityWord(share.data_visibility)).toBe("With data");
    expect(shareStateText(share)).toBe("Expires 11-20");
    expect(shareStateText({ state: "active", expires_at: null })).toBe("No expiry");
    expect(shareStateText({ state: "revoked", expires_at: null })).toBe("Revoked");
    const snap = r.value.snapshots.rows[0];
    if (!snap) throw new Error("fixture");
    expect(snapshotWindow(snap)).toBe("11-12 21:00Z–23:00Z");
  });

  it("says activity in words", () => {
    expect(activityText({ kind: "saved", version: 8, detail: "Updated dashboard settings" })).toBe(
      "Saved v8 · Updated dashboard settings",
    );
    expect(activityText({ kind: "unrecognized", version: null, detail: null })).toBe("Changed it");
  });

  it("orders diagnostics worst first, with cache and warnings in words", async () => {
    const { diagnosticsWire } = await import("./fixtures.test-support.ts");
    const { fetchDiagnostics } = await import("./api.ts");
    const original = globalThis.fetch;
    globalThis.fetch = (async () =>
      new Response(JSON.stringify({ data: diagnosticsWire }), { status: 200 })) as typeof fetch;
    try {
      const r = await fetchDiagnostics(
        { missionId: missionIdReader("m"), dashboardId: "d" },
        new AbortController().signal,
      );
      if (!r.ok) throw new Error("decode");
      const rows = worstFirst(r.value.widgets);
      expect(rows.map((w) => w.title)).toEqual(["Downlink rate", "Bus voltage"]);
      const worst = rows[0];
      if (!worst) throw new Error("fixture");
      expect(cacheText(worst)).toBe("From cache");
      expect(warningText(worst.warnings[0] ?? { code: "x", message: null })).toBe(
        "Source unavailable",
      );
    } finally {
      globalThis.fetch = original;
    }
  });

  it("parses tags", () => {
    const limits = { tags: 2, tag: 5 };
    expect(parseTags(" ops, power ,ops,", limits)).toEqual({ ok: true, tags: ["ops", "power"] });
    expect(parseTags("a,b,c", limits)).toEqual({ ok: false, message: "At most 2 tags." });
    expect(parseTags("toolong", limits).ok).toBe(false);
  });
});

describe("D3 archive in use (api-ops 3e2a6632)", () => {
  it("names the playlists from a 409 dashboard_in_use, and nothing else", async () => {
    const { usedByPlaylists } = await import("./present.ts");
    const conflict = (code: string) => ({
      kind: "conflict" as const,
      code,
      message: "x",
      details: { used_by: { playlists: [{ id: "pl1", name: "Wallboard" }] } },
    });
    expect(usedByPlaylists(conflict("dashboard_in_use"))).toEqual(["Wallboard"]);
    expect(usedByPlaylists(conflict("in_use"))).toBeNull();
  });

  it("gives authors all four tabs and everyone else Activity and Diagnostics (ux § Settings)", () => {
    expect(settingsTabs(true)).toEqual(["general", "sharing", "activity", "diagnostics"]);
    expect(settingsTabs(false)).toEqual(["activity", "diagnostics"]);
  });
});
