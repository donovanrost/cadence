import { required } from "../../../../../../test-support/required";
import { expect, test } from "vite-plus/test";
import { flushPromises, mount } from "@vue/test-utils";
import { defineComponent, h } from "vue";
import type { DiagnosticsContribution } from "@cadence/plugin-sdk";
import { ADMINISTRATION_DIAGNOSTICS_SLOT } from "@cadence/plugin-sdk";
import { admitDiagnostics } from "./contributions";
import DiagnosticsContributionBoundary from "./DiagnosticsContributionBoundary.vue";

const component = defineComponent({
  setup: () => () => h("p", { id: "healthy-panel" }, "Healthy"),
});
const contribution: DiagnosticsContribution<typeof component> = {
  id: "test.diagnostics",
  slot: ADMINISTRATION_DIAGNOSTICS_SLOT,
  version: 1,
  title: "Test diagnostics",
  order: 1,
  component,
  validate: (data) => {
    if (data !== "valid") throw new Error("private failure");
  },
};
const ready = { id: contribution.id, version: 1, status: "ready" as const, data: "valid" };

test("rejects absent, mismatched, duplicate, unavailable and malformed snapshots", () => {
  for (const snapshots of [
    [],
    [{ ...ready, id: "unknown" }],
    [{ ...ready, version: 2 }],
    [ready, ready],
    [{ ...ready, status: "unavailable" as const }],
    [{ ...ready, data: {} }],
  ]) {
    const wrapper = mount(DiagnosticsContributionBoundary, {
      props: { contribution, snapshots, interactions: { updateQuery() {} } },
    });
    expect(wrapper.find("#healthy-panel").exists()).toBe(false);
    expect(wrapper.get('[role="alert"]').text()).not.toContain("private failure");
    wrapper.unmount();
  }
});

test("contains a renderer failure and retries on a fresh snapshot without losing siblings", async () => {
  let fail = true;
  const broken = {
    ...contribution,
    component: defineComponent({
      setup() {
        return () => {
          if (fail) throw new Error("sensitive runtime error");
          return h("p", { id: "recovered" });
        };
      },
    }),
  };
  const wrapper = mount(
    defineComponent({
      render() {
        return h("main", [
          h("a", { id: "host-navigation", href: "/admin" }, "Admin"),
          h(DiagnosticsContributionBoundary, {
            contribution,
            snapshots: [ready],
            interactions: { updateQuery() {} },
          }),
          h(DiagnosticsContributionBoundary, {
            contribution: broken,
            snapshots: [ready],
            interactions: { updateQuery() {} },
          }),
        ]);
      },
    }),
  );
  await flushPromises();
  expect(wrapper.find("#host-navigation").exists()).toBe(true);
  expect(wrapper.find("#healthy-panel").exists()).toBe(true);
  expect(wrapper.get('[role="alert"]').text()).not.toContain("sensitive");
  fail = false;
  const child = required(wrapper.findAllComponents(DiagnosticsContributionBoundary)[1]);
  // Refresh arrives as a new server snapshot, clearing only this boundary's failure.
  required(child.vm.$parent).$forceUpdate();
  await flushPromises();
  expect(wrapper.find("#recovered").exists()).toBe(true);
  wrapper.unmount();
});

test("registrations are explicit, ordered and unique", () => {
  expect(
    admitDiagnostics([{ ...contribution, id: "test.later", order: 20 }, contribution]).map(
      (item) => item.id,
    ),
  ).toEqual(["test.diagnostics", "test.later"]);
  expect(() => admitDiagnostics([contribution, contribution])).toThrow();
  // @ts-expect-error Deliberately register a slot outside the supported diagnostics contract.
  expect(() => admitDiagnostics([{ ...contribution, slot: "ops.anywhere" }])).toThrow();
});
