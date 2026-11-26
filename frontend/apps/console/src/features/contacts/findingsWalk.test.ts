import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { missionId } from "@/api/index.ts";
import { fetchFindings, MAX_FINDINGS_PAGES } from "./findings.ts";

const finding = (id: string) => ({
  id,
  kind: "station_double_booked",
  severity: "critical",
  at: "2026-11-17T14:00:00Z",
  station: null,
  message: "Two passes overlap.",
  passes: [],
});
const counts = { conflicts: 1203, gaps: 7 };
const page = (ids: readonly string[], next: string | null) =>
  new Response(
    JSON.stringify({ data: { counts, findings: ids.map(finding) }, meta: { next_cursor: next } }),
  );
const window = { from: new Date("2026-11-17T00:00:00Z"), to: new Date("2026-11-18T00:00:00Z") };

afterEach(() => vi.unstubAllGlobals());

/** #793: every finding in the window, so D4 folds same-cause gaps over all of them. */
describe("fetchFindings walks every page of the window", () => {
  it("follows the cursor with the same window and keeps the whole-window counts", async () => {
    const urls: URL[] = [];
    const replies = [page(["a", "b"], "c1"), page(["c"], null)];
    vi.stubGlobal("fetch", (url: string) => {
      urls.push(new URL(url, "http://x"));
      return Promise.resolve(replies.shift() ?? new Response("{}", { status: 500 }));
    });
    const r = await fetchFindings(missionId("m-1"), window);
    expect(r.ok && r.value.findings.map((f) => f.id)).toEqual(["a", "b", "c"]);
    expect(r.ok && r.value.counts).toEqual(counts);
    expect(urls.map((u) => u.searchParams.get("cursor"))).toEqual([null, "c1"]);
    for (const u of urls) {
      expect(u.searchParams.get("from")).toBe("2026-11-17T00:00:00.000Z");
      expect(u.searchParams.get("limit")).toBe("500");
    }
  });

  it("fails the read when a later page fails", async () => {
    const replies = [page(["a"], "c1"), new Response("{}", { status: 503 })];
    vi.stubGlobal("fetch", () => Promise.resolve(replies.shift() ?? new Response("{}")));
    expect((await fetchFindings(missionId("m-1"), window)).ok).toBe(false);
  });

  it("fails, rather than looping, when the cursor never ends", async () => {
    let calls = 0;
    vi.stubGlobal("fetch", () => {
      calls += 1;
      return Promise.resolve(page([`f${calls}`], `c${calls}`));
    });
    const r = await fetchFindings(missionId("m-1"), window);
    expect(!r.ok && r.error.kind).toBe("malformed");
    expect(calls).toBe(MAX_FINDINGS_PAGES);
  });
});
