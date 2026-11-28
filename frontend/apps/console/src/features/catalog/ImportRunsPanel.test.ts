import { createMemoryHistory, createRouter } from "vue-router";
import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import type { ImportRun } from "./api.ts";
import ImportRunsPanel from "./ImportRunsPanel.vue";

const run = (over: Partial<ImportRun>): ImportRun => ({
  id: "run-1",
  file_name: "fsw.xml",
  format_label: "XTCE 1.3",
  status: "succeeded",
  diagnostic_counts: { error: 0, warning: 0, info: 0 },
  revision_number: 14,
  started_at: "2026-11-19T05:40:00Z",
  completed_at: "2026-11-19T05:41:00Z",
  requested_by: null,
  ...over,
});

async function render(runs: readonly ImportRun[], cap = 50) {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: "/", component: { render: () => null } },
      {
        path: "/setup/catalog/import/:importId?",
        name: "setup.catalog.import",
        component: { render: () => null },
      },
    ],
  });
  await router.push("/");
  return mount(ImportRunsPanel, { props: { runs, cap }, global: { plugins: [router] } });
}

describe("Import runs panel (L18)", () => {
  it("says there are no runs yet instead of an empty table", async () => {
    const wrapper = await render([]);
    expect(wrapper.text()).toContain("No import runs yet");
    expect(wrapper.find("table").exists()).toBe(false);
  });

  it("shows when each run completed, and that a running one is still parsing", async () => {
    const wrapper = await render([
      run({}),
      run({ id: "run-2", status: "running", completed_at: null, revision_number: null }),
    ]);
    const rows = wrapper.findAll("tbody tr");
    expect(rows).toHaveLength(2);
    expect(rows[0]?.text()).toMatch(/11-19 05:41/);
    expect(rows[1]?.text()).toContain("Still parsing");
  });

  it("names a run without a source file instead of breaking", async () => {
    const wrapper = await render([run({ file_name: null, format_label: null, status: "failed" })]);
    expect(wrapper.text()).toContain("Source file removed");
  });

  it("says a full page shows only the newest runs", async () => {
    const full = Array.from({ length: 3 }, (_, i) => run({ id: `run-${i}` }));
    expect((await render(full, 3)).text()).toContain("Newest 3 runs");
    expect((await render(full.slice(0, 2), 3)).text()).toContain("2 runs");
  });
});
