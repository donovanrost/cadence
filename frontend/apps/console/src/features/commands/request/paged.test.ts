import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { shallowRef } from "vue";
import { createMemoryHistory, createRouter } from "vue-router";
import { missionId } from "@/api/index.ts";
import { groupOf, showBody } from "../groups/fixtures.ts";
import type { GroupPush } from "../groups/show.ts";
import NeedsYouPanel from "./NeedsYouPanel.vue";
import TargetsPanel from "./TargetsPanel.vue";
import { listsMoved } from "./useRequest.ts";

vi.mock("@/features/fleet/index.ts", async (original) => ({
  ...(await original<typeof import("@/features/fleet/index.ts")>()),
  useFleet: () => ({ state: shallowRef({ status: "ready", value: { spacecraft: [] } }) }),
}));
afterEach(() => vi.unstubAllGlobals());

/**
 * Synthetic fixtures in the shape commanding.md "Paged targets and events" gives (#795, #1014), not
 * captured from a server: a queued group of 1,500 targets, served 100 a page.
 */
const TOTAL = 1_500;
const base = showBody.targets[0];
if (!base) throw new Error("fixture");
const target = (i: number, stage = "queued_for_contact") => ({
  ...base,
  index: i,
  spacecraft_id: `sc-${i}`,
  name: `EARENDIL-${String(i).padStart(4, "0")}`,
  scid: 100 + i,
  stage,
  members: [{ ...base.members[0], stage, failure_reason: null }],
});
const group = (revision = 1, progress: Record<string, number> = { queued_for_contact: TOTAL }) =>
  groupOf({
    state: "queued",
    target_count: TOTAL,
    member_count: TOTAL,
    progress,
    targets: Array.from({ length: 100 }, (_, i) => target(i)),
    targets_page: { total: TOTAL, revision, next_cursor: "100" },
  });

function server(serve: (url: URL) => unknown) {
  const asked: URL[] = [];
  vi.stubGlobal(
    "fetch",
    vi.fn((input: string) => {
      const url = new URL(input, "http://x");
      asked.push(url);
      return Promise.resolve(new Response(JSON.stringify(serve(url)), { status: 200 }));
    }),
  );
  return asked;
}
const pageOf = (url: URL, all: (i: number) => unknown, total: number) => {
  const limit = Number(url.searchParams.get("limit") ?? "100");
  const from = Number(url.searchParams.get("cursor") ?? "0");
  const to = Math.min(from + limit, total);
  return {
    data: { targets: Array.from({ length: to - from }, (_, i) => all(from + i)) },
    meta: { total, next_cursor: to < total ? String(to) : null },
  };
};

describe("U1 Targets for a group of 1,500 (#795)", () => {
  it("shows a page, says how many of the whole, and Load more reads the next", async () => {
    const asked = server((url) => pageOf(url, (i) => target(i), TOTAL));
    const w = mount(TargetsPanel, { props: { group: group(), missionId: missionId("m-1") } });
    await flushPromises();
    expect(w.findAll("li")).toHaveLength(100);
    expect(w.text()).toContain("100 of 1,500 shown");
    const more = w.findAll("button").find((b) => b.text() === "Load more");
    await more?.trigger("click");
    await flushPromises();
    expect(w.findAll("li")).toHaveLength(200);
    expect(w.text()).toContain("200 of 1,500 shown");
    expect(asked.map((u) => u.searchParams.get("cursor"))).toEqual([null, "100"]);
  });

  it("reads its pages again when a target's stage moves (the revision), not otherwise", async () => {
    const asked = server((url) => pageOf(url, (i) => target(i), TOTAL));
    const w = mount(TargetsPanel, { props: { group: group(1), missionId: missionId("m-1") } });
    await flushPromises();
    await w.setProps({ group: group(1) });
    await flushPromises();
    expect(asked).toHaveLength(1);
    await w.setProps({ group: group(2) });
    await flushPromises();
    expect(asked).toHaveLength(2);
  });

  it("tags a paged target whose model approval was withdrawn after GO (E2c, #546)", async () => {
    const flag = {
      revision_id: "mm-4",
      decision: { kind: "withdrawn", by: null, at: "2026-11-27T10:02:00Z", reason: null },
    };
    server((url) =>
      pageOf(url, (i) => ({ ...target(i), withdrawn_after_go: i === 1 ? flag : null }), TOTAL),
    );
    const w = mount(TargetsPanel, { props: { group: group(), missionId: missionId("m-1") } });
    await flushPromises();
    const tagged = w.findAll("li").map((li) => li.text().includes("Approval withdrawn after GO"));
    expect(tagged.slice(0, 3)).toEqual([false, true, false]);
    expect(tagged.filter(Boolean)).toHaveLength(1);
  });
});

describe("N Needs you for a group of 1,500 (#795)", () => {
  it("asks the server for exactly its targets, with the member's own failure reason", async () => {
    const failed = (i: number) => ({
      ...target(i, "verify_failed"),
      members: [{ ...base.members[0], stage: "verify_failed", failure_reason: "verify_timed_out" }],
    });
    const asked = server((url) => pageOf(url, failed, 120));
    const stub = { render: () => null };
    const router = createRouter({
      history: createMemoryHistory(),
      routes: [
        { path: "/", component: stub },
        { path: "/new", name: "ops.commands.new", component: stub },
        { path: "/sc/:scId/:tab?", name: "ops.spacecraft", component: stub },
      ],
    });
    const w = mount(NeedsYouPanel, {
      global: { plugins: [router] },
      props: {
        group: group(1, { queued_for_contact: 1_380, verify_failed: 120 }),
        series: null,
        missionId: missionId("m-1"),
      },
    });
    await flushPromises();
    expect(asked[0]?.searchParams.get("needs_you")).toBe("true");
    expect(w.text()).toContain("FORCE_WATCHDOG was sent, but verification timed out.");
    expect(w.text()).toContain("100 of 120 shown");
    // Re-send names only the targets read, and says so.
    expect(w.text()).toContain("Re-send to the 100 shown");
  });
});

describe("the group push (#795)", () => {
  it("asks for the lists again only when a stage moved or events were added", () => {
    const shown = group(7);
    const push = (revision: number, total: number): GroupPush => ({
      ...shown,
      targets_page: { ...shown.targets_page, revision },
      events_page: { ...shown.events_page, total },
    });
    const events = shown.events_page.total;
    expect(listsMoved(shown, push(7, events))).toBe(false);
    expect(listsMoved(shown, push(8, events))).toBe(true);
    expect(listsMoved(shown, push(7, events + 1))).toBe(true);
  });
});
