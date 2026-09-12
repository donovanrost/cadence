import { required } from "../../../../../test-support/required";
import { afterEach, expect, test, vi } from "vite-plus/test";
import { flushPromises, mount } from "@vue/test-utils";
import { sharedViewFixture, sharedViewContext } from "./fixtures.test-support";
import { shareContribution, snapshotContribution } from "./contribution";
import SharedDashboardView from "./SharedDashboardView.vue";
import SharedViewLegacyRedirect from "./SharedViewLegacyRedirect.vue";
import { readSharedView } from "./validation";
const wrappers: { unmount: () => void }[] = [];
afterEach(() => wrappers.splice(0).forEach((w) => w.unmount()));
function setup(kind: "share" | "snapshot" = "snapshot", dataOnly = false) {
  const model = sharedViewFixture(kind);
  if (dataOnly) {
    model.data_visibility = "definition_only";
    model.canvas = null;
  }
  const navigate = vi.fn((_: string) => {}),
    refresh = vi.fn(async () => {});
  const wrapper = mount(SharedDashboardView, {
    props: {
      model,
      context: sharedViewContext(kind),
      port: { execute: vi.fn(), navigate },
      refresh,
    },
  });
  wrappers.push(wrapper);
  return { wrapper, model, navigate, refresh };
}
test.each(["share", "snapshot"] as const)(
  "%s viewer leaves the main landmark to the host",
  (kind) => {
    const { wrapper } = setup(kind);
    expect(wrapper.get("#shared-dashboard-feature").element.tagName).toBe("SECTION");
    expect(wrapper.findAll('main, [role="main"]')).toHaveLength(0);
  },
);
test("snapshot viewer renders real read-time values and the exact complete definition without author controls", () => {
  const { wrapper } = setup();
  expect(wrapper.get("#shared-view-version").text()).toBe("Captured v1");
  expect(wrapper.get("#shared-view-definition pre").text()).toContain('"placement_id": "battery"');
  expect(wrapper.text()).toContain("28.4");
  expect(wrapper.find("#dashboard-viewer-context-form").exists()).toBe(false);
  expect(wrapper.find("#dashboard-viewer-edit").exists()).toBe(false);
  expect(wrapper.get("#shared-view-semantics").text()).toContain("not a live stream");
});
test("definition-only access renders no runtime canvas and refresh retains its disclosure", async () => {
  const { wrapper, refresh } = setup("snapshot", true);
  expect(wrapper.find("[data-workspace-snapshot]").exists()).toBe(false);
  expect(wrapper.get("#shared-view-visibility").text()).toContain("runtime data withheld");
  const details = wrapper.get("#shared-view-definition").element;
  await wrapper.get("#shared-view-refresh").trigger("click");
  await flushPromises();
  expect(refresh).toHaveBeenCalledOnce();
  expect(wrapper.get("#shared-view-definition").element).toBe(details);
});
test("shares without a published definition have an explicit state and host navigation", async () => {
  const { wrapper, model, navigate } = setup("share");
  await wrapper.setProps({ model: { ...model, definition: null, canvas: null } });
  expect(wrapper.find("#shared-view-unpublished").exists()).toBe(true);
  expect(wrapper.find("#shared-view-definition").exists()).toBe(false);
  await wrapper.get("#shared-view-directory").trigger("click");
  expect(navigate).toHaveBeenCalledExactlyOnceWith("/missions/mission/ops/dashboards");
});
test("refresh failure is visible and single-flight without replacing displayed data", async () => {
  const { wrapper } = setup("snapshot", true);
  let reject!: (e: Error) => void;
  const refresh = vi.fn(() => new Promise<void>((_, r) => (reject = r)));
  await wrapper.setProps({ refresh });
  await wrapper.get("#shared-view-refresh").trigger("click");
  await wrapper.get("#shared-view-refresh").trigger("click");
  expect(refresh).toHaveBeenCalledOnce();
  reject(Error("offline"));
  await flushPromises();
  expect(wrapper.get("#shared-view-error").text()).toContain("last successful read");
  expect(wrapper.get("#shared-view-version").text()).toBe("Captured v1");
});
test("contribution contracts reject identity, version, visibility and renderer authority forgery", () => {
  const fixture = sharedViewFixture();
  expect(snapshotContribution.read(fixture, sharedViewContext()).model).toEqual(fixture);
  expect(shareContribution.actions).toEqual([]);
  expect(snapshotContribution.actions).toEqual([]);
  for (const patch of [
    { id: "foreign" },
    { organization_id: "foreign" },
    { kind: "share" },
    { version: 2 },
    { component: "Arbitrary" },
    { data_visibility: "definition_only" },
    { canvas: { ...required(fixture.canvas), author: true } },
    { canvas: { ...required(fixture.canvas), document_mode: "published" } },
    { canvas: { ...required(fixture.canvas), document_version: 99 } },
    {
      canvas: {
        ...required(fixture.canvas),
        placements: [{ ...required(fixture.canvas).placements[0], authored_id: "foreign" }],
      },
    },
    {
      definition: {
        ...required(fixture.definition),
        json: required(fixture.definition).json.replace('"mission"', '"foreign"'),
      },
    },
    { runtime_context: { javascript: "arbitrary" } },
    { runtime_context: { realm: "unapproved" } },
    { data_semantics: "frozen_time_window" },
  ])
    expect(() =>
      readSharedView({ ...fixture, ...patch }, sharedViewContext(), "snapshot"),
    ).toThrow();
});
test("legacy entries link only to canonical scoped host viewers", async () => {
  const wrapper = mount(SharedViewLegacyRedirect, {
    props: { mission_id: "mission", share_id: "share-1" },
  });
  wrappers.push(wrapper);
  expect(wrapper.get("#shared-view-open-workspace").attributes("href")).toBe(
    "/missions/mission/ops/dashboard-shares/share-1",
  );
  // @ts-expect-error Vue runtime reconciliation removes the optional share ID before switching viewers.
  await wrapper.setProps({ share_id: undefined, snapshot_id: "snapshot-1" });
  expect(wrapper.get("#shared-view-open-workspace").attributes("href")).toBe(
    "/missions/mission/ops/dashboard-snapshots/snapshot-1",
  );
  await wrapper.setProps({ snapshot_id: "../foreign" });
  expect(wrapper.find("#shared-view-open-workspace").exists()).toBe(false);
});
