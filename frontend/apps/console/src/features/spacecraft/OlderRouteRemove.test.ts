import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { createMemoryHistory, createRouter } from "vue-router";
import { missionId } from "@/api/index.ts";
import { configWith, olderRules } from "./older-route.fixtures.ts";
import RoutingRulesPanel from "./RoutingRulesPanel.vue";

// The panel reads the open set (useConfigState), which listens for config changes live.
vi.mock("@/live", async (original) => ({
  ...(await original<typeof import("@/live")>()),
  useMissionInvalidation: () => undefined,
}));

/** ux U79: Remove… on an older route, through the panel, against stubbed reads. */
afterEach(() => vi.unstubAllGlobals());
async function render(ops: readonly Record<string, unknown>[], mission = "m-1") {
  const sent: unknown[] = [];
  vi.stubGlobal("fetch", (url: string, init?: RequestInit) => {
    if (typeof init?.body === "string") sent.push(JSON.parse(init.body));
    const data = url.endsWith("/stage")
      ? {
          change_set_id: "cs-1",
          change_id: "c-1",
          version: 1,
          staged_count: 1,
          base_revision: 5,
          entity_ids: ["old-1"],
        }
      : url.endsWith("/config")
        ? configWith(ops)
        : {};
    return Promise.resolve(new Response(JSON.stringify({ data })));
  });
  const stub = { render: () => null };
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: "/sc", name: "setup.spacecraft.one", component: stub },
      { path: "/changes", name: "setup.changes", component: stub },
      { path: "/comms", name: "setup.comms", component: stub },
    ],
  });
  await router.push("/sc");
  const w = mount(RoutingRulesPanel, {
    props: {
      missionId: missionId(mission),
      spacecraftName: "EARENDIL-389",
      rules: olderRules(),
      canStage: true,
    },
    global: { plugins: [router] },
    attachTo: document.body,
  });
  await flushPromises();
  return { w, sent };
}
const buttons = () => [...document.querySelectorAll("button")];

describe("older route Remove… (ux U79)", () => {
  it("confirms in place, then stages the legacy_routing_rule delete with ux's summary", async () => {
    const { w, sent } = await render([], "m-remove");
    const row = w.findAll("tr").find((tr) => tr.text().includes("qa-pre-routing-175358"));
    expect(row?.text()).toContain("Older routes can't be edited here until they're converted.");
    buttons()
      .find((b) => b.textContent?.trim() === "Remove…")
      ?.click();
    await flushPromises();
    expect(document.body.textContent).toContain(
      "Stage removing “qa-pre-routing-175358”? EARENDIL-389 stops using it once the change set is applied.",
    );
    buttons()
      .find((b) => b.textContent?.trim() === "Stage removal")
      ?.click();
    await flushPromises();
    expect(sent).toContainEqual({
      summary: "Remove older route “qa-pre-routing-175358” · EARENDIL-389",
      source: { surface: "spacecraft" },
      ops: [{ kind: "legacy_routing_rule", action: "delete", entity_id: "old-1" }],
    });
    w.unmount();
  });

  it("a conversion_in_progress refusal keeps its Open change set link (U79; #405 review)", async () => {
    const { w } = await render([], "m-converting");
    vi.stubGlobal("fetch", (url: string) => {
      if (url.endsWith("/stage"))
        return Promise.resolve(
          new Response(
            JSON.stringify({
              error: {
                code: "conversion_in_progress",
                message: "A conversion batch is staged.",
                details: { change_set_id: "cs-9", batch: 3 },
              },
            }),
            { status: 409 },
          ),
        );
      const data = url.endsWith("/config") ? configWith([]) : {};
      return Promise.resolve(new Response(JSON.stringify({ data })));
    });
    buttons()
      .find((b) => b.textContent?.trim() === "Remove…")
      ?.click();
    await flushPromises();
    buttons()
      .find((b) => b.textContent?.trim() === "Stage removal")
      ?.click();
    await flushPromises();
    expect(document.body.textContent).toContain(
      "Batch 3 of the route conversion is staged, so other changes can't be staged in this mission until it's applied or discarded.",
    );
    const row = w.findAll("tr").find((tr) => tr.text().includes("qa-pre-routing-175358"));
    expect(row?.findAll("a").map((a) => a.text())).toContain("Open change set");
    w.unmount();
  });

  it("says 'Removal staged' with Open change set once the open set holds it", async () => {
    const { w } = await render(
      [{ kind: "legacy_routing_rule", action: "delete", entity_id: "old-1" }],
      "m-staged",
    );
    const row = w.findAll("tr").find((tr) => tr.text().includes("qa-pre-routing-175358"));
    expect(row?.text()).toContain("Removal staged");
    expect(row?.findAll("a").map((a) => a.text())).toContain("Open change set");
    expect(row?.text()).not.toContain("Remove…");
    w.unmount();
  });
});
