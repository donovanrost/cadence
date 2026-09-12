import { fixtureArrayAt, fixtureRecordAt } from "../../../../../test-support/json-fixture";
import { expect, test, vi } from "vite-plus/test";
import { mount } from "@vue/test-utils";
import { diagnosticsFixture } from "./fixtures.test-support";
import RuntimeDiagnosticsContribution from "./RuntimeDiagnosticsContribution.vue";
import { assertRuntimeDiagnostics } from "./validation";

test("renders the real feature and translates filters into host query navigation", async () => {
  const data = diagnosticsFixture();
  assertRuntimeDiagnostics(data);
  const updateQuery = vi.fn();
  const wrapper = mount(RuntimeDiagnosticsContribution, {
    props: { data, interactions: { updateQuery } },
  });
  expect(wrapper.find("#admin-runtime-decisions-empty").exists()).toBe(true);
  expect(wrapper.find("h1").exists()).toBe(false);
  await wrapper.get("#runtime_decision_filters_dashboard_id").setValue("dashboard-a");
  expect(updateQuery).toHaveBeenLastCalledWith({
    ...data.filters.values,
    dashboard_id: "dashboard-a",
  });
  wrapper.unmount();
});

test("validates nested fields instead of admitting an arbitrary props map", () => {
  for (const mutate of [
    (data: unknown) => {
      delete fixtureRecordAt(data, "filters").values;
    },
    (data: unknown) => {
      fixtureRecordAt(data, "filters", "fields", 0).key = "authorization";
    },
    (data: unknown) => {
      fixtureArrayAt(data, "decisions").push({ id: "incomplete" });
    },
    (data: unknown) => {
      fixtureRecordAt(data, "summary", "stats", 0).value = "zero";
    },
    (data: unknown) => {
      fixtureRecordAt(data, "selection").detail = {};
    },
    (data: unknown) => {
      fixtureRecordAt(data, "filters").clear_href = "https://untrusted.invalid";
    },
    (data: unknown) => {
      fixtureRecordAt(data, "selection").context_href = "javascript:alert(1)";
    },
  ]) {
    const data = diagnosticsFixture();
    mutate(data);
    expect(() => assertRuntimeDiagnostics(data)).toThrow("contract");
  }
});

test("renders selected decision evidence and retains its navigation links", () => {
  const data = diagnosticsFixture();
  data.decisions = [
    {
      __dom_id: "decision-row-1",
      id: "decision-row-1",
      key: "decision-1",
      dashboard: "dashboard-a",
      mission: "mission-a",
      source: "durable",
      boundary: "source_watermark_changed",
      status: "filtered",
      context: "replay_run_mismatch",
      replay_run: "replay-a",
      refresh: "suppressed",
      artifacts: "2",
      affected_count: "1",
      affected_placements: "placement-a",
      affected_impact: "primary_source",
      observed: "2026-09-06T00:00:00Z",
      inspect_action: {
        id: "inspect-decision-1",
        href: "/admin/runtime?decision=decision-1",
        selected: true,
      },
    },
  ];
  data.summary.decision_count = 1;
  data.summary.selected_decision_state = "visible";
  data.selection = {
    state: "visible",
    decision_key: "decision-1",
    missing: false,
    outside_results: false,
    context_href: null,
    detail: {
      id: "admin-runtime-decision-detail",
      subtitle: "Selected decision",
      close_action: { id: "close-decision", href: "/admin/runtime" },
      evidence: {
        id: "decision-evidence",
        decision_key: "decision-1",
        source: "durable",
        groups: [
          {
            key: "identity",
            label: "Identity",
            facts: [{ key: "dashboard", label: "Dashboard", value: "dashboard-a" }],
          },
        ],
      },
      sections: [
        {
          id: "decision-filters",
          key: "filters",
          label: "Filters",
          empty_copy: "No filters",
          pairs: [],
        },
      ],
    },
  };
  assertRuntimeDiagnostics(data);
  const wrapper = mount(RuntimeDiagnosticsContribution, {
    props: { data, interactions: { updateQuery() {} } },
  });
  expect(wrapper.get("#decision-row-1").text()).toContain("dashboard-a");
  expect(wrapper.get("#inspect-decision-1").attributes("aria-current")).toBe("true");
  expect(wrapper.get("#inspect-decision-1").attributes("href")).toBe(
    "/admin/runtime?decision=decision-1",
  );
  expect(wrapper.get("#decision-evidence").attributes("data-runtime-decision-detail-key")).toBe(
    "decision-1",
  );
  expect(wrapper.get("#close-decision").attributes("href")).toBe("/admin/runtime");
  expect(wrapper.find("#admin-runtime-decisions-empty").exists()).toBe(false);
  wrapper.unmount();
});
