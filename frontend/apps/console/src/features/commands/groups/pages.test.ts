import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { decode, missionId } from "@/api/index.ts";
import { preflightReader } from "./api.ts";
import { MAX_TARGETS } from "./bounds.ts";
import { groupOf, showBody } from "./fixtures.ts";
import { fetchAllEvents, fetchAllTargets, fetchTargetsPage } from "./pages.ts";
import { groupPushReader, groupReader } from "./show.ts";

afterEach(() => vi.unstubAllGlobals());

/**
 * Synthetic fixtures in the shape commanding.md "Paged targets and events" gives (#795, #1014), not
 * captured from a server: a group of 1,500 targets, more than any page and than the old 1,000 cap.
 */
const TOTAL = 1_500;
const base = showBody.targets[0];
if (!base) throw new Error("fixture");
const target = (i: number) => ({
  ...base,
  index: i,
  spacecraft_id: `sc-${i}`,
  name: `EARENDIL-${String(i).padStart(4, "0")}`,
  scid: 100 + i,
});

/** A targets read that pages `TOTAL` targets by a numeric cursor, as the server's opaque one. */
function server() {
  const asked: URL[] = [];
  vi.stubGlobal(
    "fetch",
    vi.fn((input: string) => {
      const url = new URL(input, "http://x");
      asked.push(url);
      const limit = Number(url.searchParams.get("limit") ?? "100");
      const from = Number(url.searchParams.get("cursor") ?? "0");
      const to = Math.min(from + limit, TOTAL);
      const body = {
        data: { targets: Array.from({ length: to - from }, (_, i) => target(from + i)) },
        meta: { total: TOTAL, next_cursor: to < TOTAL ? String(to) : null },
      };
      return Promise.resolve(new Response(JSON.stringify(body), { status: 200 }));
    }),
  );
  return asked;
}

describe("a group of 1,500 targets (#795)", () => {
  it("decodes the read's first page with the totals, and a push without the lists", () => {
    const first = Array.from({ length: 100 }, (_, i) => target(i));
    const g = groupOf({
      target_count: TOTAL,
      member_count: TOTAL,
      targets: first,
      targets_page: { total: TOTAL, unnamed: 0, revision: 42, next_cursor: "100" },
    });
    expect([g.targets.length, g.targets_page.total, g.targets[99]?.index]).toEqual([
      100,
      TOTAL,
      99,
    ]);
    const { targets: _t, events: _e, ...push } = { ...showBody, target_count: TOTAL };
    const pushed = decode(groupPushReader, push);
    expect(pushed.ok && pushed.value.targets_page.total).toBe(1);
    // The read refuses a first page past what a page can carry, never trims it silently.
    const tooMany = Array.from({ length: 501 }, (_, i) => target(i));
    expect(decode(groupReader, { ...showBody, targets: tooMany }).ok).toBe(false);
  });

  it("reads the re-check of a 1,500-target request (the old cap was 1,000)", () => {
    const r = decode(preflightReader, {
      valid: true,
      digest: "d",
      members: TOTAL,
      second_go_required: true,
      targets: Array.from({ length: TOTAL }, (_, i) => ({
        index: i,
        spacecraft_id: `sc-${i}`,
        source_endpoint_id: null,
        name: null,
        scid: null,
        failure: null,
      })),
      checks: [],
    });
    expect(r.ok && r.value.targets.length).toBe(TOTAL);
    expect(MAX_TARGETS).toBe(5_000);
  });

  it("asks a page with its filters, and walks every page for the resend clone", async () => {
    const asked = server();
    const key = { missionId: missionId("m-1"), groupId: "grp-1" };
    const one = await fetchTargetsPage(
      { ...key, stages: ["verify_failed", "release_failed"], q: "earendil", needsYou: true },
      "200",
      new AbortController().signal,
    );
    expect(one.ok && [one.value.items[0]?.index, one.value.meta.total]).toEqual([200, TOTAL]);
    const params = asked[0]?.searchParams;
    expect([
      asked[0]?.pathname,
      params?.get("limit"),
      params?.get("stage"),
      params?.get("q"),
      params?.get("needs_you"),
      params?.get("cursor"),
    ]).toEqual([
      "/api/v1/missions/m-1/command-groups/grp-1/targets",
      "100",
      "verify_failed,release_failed",
      "earendil",
      "true",
      "200",
    ]);

    const all = await fetchAllTargets(key, new AbortController().signal);
    expect(all.ok && all.value.length).toBe(TOTAL);
    expect(all.ok && new Set(all.value.map((t) => t.spacecraft_id)).size).toBe(TOTAL);
    // 500 a page: three requests for 1,500, never one per target.
    expect(asked.slice(1).map((u) => u.searchParams.get("limit"))).toEqual(["500", "500", "500"]);
  });

  it("reads every event of a kind, oldest first, across pages", async () => {
    const asked: URL[] = [];
    const ack = (n: number) => ({
      id: `ev-${n}`,
      kind: "hold_acknowledged",
      actor: { actor_kind: "user", user_id: "u-1" },
      at: `2026-11-08T02:00:0${n}Z`,
      payload: { key: "conflicts", note: `ack ${n}` },
    });
    vi.stubGlobal(
      "fetch",
      vi.fn((input: string) => {
        const url = new URL(input, "http://x");
        asked.push(url);
        // The first page is the latest; the cursor reads back to older ones.
        const older = url.searchParams.get("cursor") === "older";
        const body = {
          data: { events: older ? [ack(1), ack(2)] : [ack(3)] },
          meta: { total: 3, next_cursor: older ? null : "older" },
        };
        return Promise.resolve(new Response(JSON.stringify(body), { status: 200 }));
      }),
    );
    const r = await fetchAllEvents(
      { missionId: missionId("m-1"), groupId: "grp-1", kinds: ["hold_acknowledged"] },
      new AbortController().signal,
    );
    expect(r.ok && r.value.map((e) => e.id)).toEqual(["ev-1", "ev-2", "ev-3"]);
    expect(asked[0]?.searchParams.get("kind")).toBe("hold_acknowledged");
  });
});
