import { afterEach, beforeEach, describe, expect, it, vi } from "vite-plus/test";
import { missionId } from "@/api/index.ts";
import { fetchPasses, MAX_PASS_PAGES } from "./passes-api.ts";

const pass = (id: string, o: Record<string, unknown> = {}) => ({
  id,
  kind: "contact",
  state: "confirmed",
  pass_phase: "scheduled",
  delivery_state: "pending",
  spacecraft_id: "spacecraft-earendil-003",
  spacecraft: { id: "spacecraft-earendil-003", name: "EARENDIL-003", scid: 3 },
  station: { ref: "brs", id: null, code: "BRS", name: "Brisbane" },
  antenna: null,
  starts_at: "2026-11-17T14:00:00Z",
  ends_at: "2026-11-17T14:10:00Z",
  uplink_capable: true,
  source: { provider: "p-1", provider_name: "Northlight", synthetic: false },
  max_elevation_deg: null,
  elevation_source: null,
  predicted_pass_id: null,
  plan: null,
  attention: null,
  ...o,
});
const counts = {
  total: 1203,
  booked: 1100,
  hand_started: 3,
  in_contact: 41,
  upcoming: 900,
  synthetic: 0,
};
const page = (ids: readonly string[], next: string | null, extra: unknown[] = []) =>
  new Response(
    JSON.stringify({
      data: {
        from: "2026-11-17T00:00:00Z",
        to: "2026-11-18T00:00:00Z",
        counts,
        passes: [...ids.map((id) => pass(id)), ...extra],
      },
      meta: { next_cursor: next },
    }),
  );
const window = { from: new Date("2026-11-17T00:00:00Z"), to: new Date("2026-11-18T00:00:00Z") };

beforeEach(() => vi.spyOn(console, "warn").mockImplementation(() => {}));
afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

/** #793: GET /passes pages are walked to the end; no window is ever shown cut short. */
describe("fetchPasses walks every page of the window", () => {
  it("follows the cursor with the same window and filters, and keeps the whole-window counts", async () => {
    const urls: URL[] = [];
    const replies = [
      page(["a", "b"], "c1"),
      page(["c"], "c2", [pass("bad", { state: 7 })]),
      page(["d"], null),
    ];
    vi.stubGlobal("fetch", (url: string) => {
      urls.push(new URL(url, "http://x"));
      return Promise.resolve(replies.shift() ?? new Response("{}", { status: 500 }));
    });
    const r = await fetchPasses(missionId("m-1"), { ...window, station: "BRS" });
    expect(r.ok && r.value.passes.map((p) => p.id)).toEqual(["a", "b", "c", "d"]);
    expect(r.ok && r.value.unshown).toEqual([{ kind: ["contact"], id: "bad" }]);
    expect(r.ok && r.value.counts).toEqual(counts);
    expect(urls.map((u) => u.searchParams.get("cursor"))).toEqual([null, "c1", "c2"]);
    for (const u of urls) {
      expect(u.searchParams.get("from")).toBe("2026-11-17T00:00:00.000Z");
      expect(u.searchParams.get("to")).toBe("2026-11-18T00:00:00.000Z");
      expect(u.searchParams.get("station")).toBe("BRS");
      expect(u.searchParams.get("limit")).toBe("500");
    }
  });

  it("fails the whole read when a later page fails, never showing a partial window", async () => {
    const replies = [page(["a"], "c1"), new Response("{}", { status: 503 })];
    vi.stubGlobal("fetch", () => Promise.resolve(replies.shift() ?? new Response("{}")));
    const r = await fetchPasses(missionId("m-1"), window);
    expect(r.ok).toBe(false);
  });

  it("fails, rather than looping, when the cursor never ends (console-eng on #906)", async () => {
    let calls = 0;
    vi.stubGlobal("fetch", () => {
      calls += 1;
      return Promise.resolve(page([`p${calls}`], `c${calls}`));
    });
    const r = await fetchPasses(missionId("m-1"), window);
    expect(r.ok).toBe(false);
    expect(!r.ok && r.error.kind).toBe("malformed");
    expect(calls).toBe(MAX_PASS_PAGES);
  });
});
