import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { createMemoryHistory, createRouter } from "vue-router";
import { missionId } from "@/api/index.ts";
import RollbackPanel from "./RollbackPanel.vue";

/** #413: a staging refusal on Roll back keeps its way out (e.g. Open the report). */
afterEach(() => vi.unstubAllGlobals());

const preview = {
  target: 3,
  head: 5,
  reverts: [4, 5],
  summary: "Roll back to r3",
  ops: [{ kind: "transport", entity_id: "t-1", action: "update" }],
  outside: [],
  preview: {
    verdict: "go",
    checks: [{ key: "compatibility", verdict: "go", items: [] }],
    effects: [],
  },
};

describe("Roll back: a staging refusal (#413)", () => {
  it("shows a refusal with its way out and stays on the page", async () => {
    vi.stubGlobal("fetch", (_url: string, init?: RequestInit) =>
      Promise.resolve(
        init?.method === "POST"
          ? new Response(
              JSON.stringify({
                error: {
                  code: "mission_model_comparison_failed",
                  message: "Not staged: the model comparison failed.",
                  details: { mission_model_revision_id: "mmr-9" },
                },
              }),
              { status: 409 },
            )
          : new Response(JSON.stringify({ data: preview })),
      ),
    );
    const stub = { render: () => null };
    const router = createRouter({
      history: createMemoryHistory(),
      routes: [
        { path: "/revisions", name: "setup.changes.revisions", component: stub },
        { path: "/model/:revisionId", name: "setup.catalog.model", component: stub },
      ],
    });
    await router.push("/revisions");
    const w = mount(RollbackPanel, {
      props: { missionId: missionId("m-1"), to: 3, stagedCount: 0 },
      global: {
        plugins: [router],
        // The preview body's entity links read the mission scope; this test is about the refusal.
        stubs: {
          AppInstallLinks: true,
          ModelApprovalLinks: true,
          AlarmLinks: true,
          DependentLinks: true,
        },
      },
      attachTo: document.body,
    });
    await w
      .findAll("button")
      .find((b) => b.text() === "Roll back to r3")
      ?.trigger("click");
    await flushPromises();
    await w
      .findAll("button")
      .find((b) => b.text().startsWith("Stage rollback"))
      ?.trigger("click");
    await flushPromises();
    expect(w.text()).toContain("Not staged: the model comparison failed.");
    const open = w.findAll("a").find((a) => a.text() === "Open the report");
    expect(open?.attributes("href")).toBe("/model/mmr-9");
    expect(router.currentRoute.value.name).toBe("setup.changes.revisions");
    w.unmount();
  });
});
