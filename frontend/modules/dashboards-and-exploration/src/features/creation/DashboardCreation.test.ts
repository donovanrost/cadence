import { afterEach, expect, test, vi } from "vite-plus/test";
import { mount, flushPromises } from "@vue/test-utils";
import { creationContribution } from "./contribution";
import DashboardCreation from "./DashboardCreation.vue";
import { readCreation } from "./validation";
import type { CreationState } from "./contracts";
import type { OpsPagePort } from "@cadence/plugin-sdk/ops-pages";
const state = (mode: "new" | "clone" | "import" = "new"): CreationState => ({
  sequence: 0,
  phase: "editing",
  model: {
    version: 1,
    mission_id: "mission-1",
    mode,
    source:
      mode === "clone"
        ? { id: "source-1", name: "Flight", description: "Thermal", version: 3, widget_count: 4 }
        : null,
  },
});
const wrappers: { unmount: () => void }[] = [];
afterEach(() => {
  for (const w of wrappers.splice(0)) w.unmount();
});
function setup(
  s = state(),
  execute: OpsPagePort["execute"] = vi.fn(async () => ({ status: "unknown", sequence: 1 })),
) {
  const navigate = vi.fn((_: string) => {}),
    refresh = vi.fn(async () => {});
  const wrapper = mount(DashboardCreation, {
    props: { state: s, port: { execute, navigate }, refresh },
  });
  wrappers.push(wrapper);
  return { wrapper, execute, navigate, refresh };
}
test("admits finite semantic creation DTOs and rejects mismatched modes, sources and context", () => {
  for (const mode of ["new", "clone", "import"] as const)
    expect(readCreation(state(mode), "mission-1")).toEqual(state(mode));
  for (const bad of [
    { ...state(), phase: "complete" },
    { ...state(), sequence: 1.5 },
    { ...state(), model: { ...state().model, mission_id: "foreign" } },
    { ...state(), model: { ...state().model, version: 2 } },
    { ...state(), model: { ...state().model, mode: "clone" } },
    {
      ...state("clone"),
      model: { ...state("clone").model, source: { ...state("clone").model.source, version: 0 } },
    },
  ])
    expect(() => readCreation(bad, "mission-1")).toThrow();
  expect(() =>
    creationContribution.read(state(), {
      organizationId: "org",
      missionId: "mission-1",
      resourceId: "unexpected",
    }),
  ).toThrow();
});
test("preserves native controls and draft through context refresh", async () => {
  const { wrapper } = setup();
  const input = wrapper.get("#dashboard-name").element;
  await wrapper.get("#dashboard-name").setValue("My draft");
  await wrapper.setProps({ state: { ...state(), model: { ...state().model } } });
  expect(wrapper.get("#dashboard-name").element).toBe(input);
  expect((input as HTMLInputElement).value).toBe("My draft");
  expect(wrapper.get("#dashboard-new-cancel").attributes("href")).toBe(
    "/missions/mission-1/ops/dashboards",
  );
});
test("submits once with the displayed clone version and navigates only on a matching receipt", async () => {
  const execute = vi.fn(async () => ({
    status: "ok",
    sequence: 1,
    data: { dashboard_id: "new/id", version: 1, mode: "clone" },
  }));
  const { wrapper, navigate } = setup(state("clone"), execute);
  expect((wrapper.get("#dashboard-name").element as HTMLInputElement).value).toBe("Copy of Flight");
  await wrapper.get("#dashboard-new-form").trigger("submit");
  await flushPromises();
  expect(execute).toHaveBeenCalledWith("create", {
    sequence: 1,
    source_version: 3,
    dashboard: { name: "Copy of Flight", description: "Thermal" },
  });
  expect(navigate).toHaveBeenCalledWith("/missions/mission-1/ops/dashboards/new%2Fid/edit");
  await wrapper.get("#dashboard-new-form").trigger("submit");
  expect(execute).toHaveBeenCalledTimes(1);
});
test("corrects a rejected import without losing JSON or name and uses the next sequence", async () => {
  const execute = vi
    .fn()
    .mockResolvedValueOnce({ status: "invalid", sequence: 1, code: "document" })
    .mockResolvedValue({ status: "unknown", sequence: 2 });
  const { wrapper } = setup(state("import"), execute);
  await wrapper.get("#dashboard-name").setValue("Imported");
  await wrapper.get("#dashboard-document-json").setValue("{bad}");
  await wrapper.get("#dashboard-new-form").trigger("submit");
  await flushPromises();
  expect(wrapper.get("#dashboard-new-submit").attributes("disabled")).toBeUndefined();
  expect((wrapper.get("#dashboard-document-json").element as HTMLTextAreaElement).value).toBe(
    "{bad}",
  );
  await wrapper.get("#dashboard-document-json").setValue("{}");
  await wrapper.get("#dashboard-new-form").trigger("submit");
  await flushPromises();
  expect(execute).toHaveBeenLastCalledWith("create", {
    sequence: 2,
    source_version: null,
    dashboard: { name: "Imported", description: "", document_json: "{}" },
  });
});
test("unknown, rejected, transport failure and malformed receipts never unlock on refresh", async () => {
  for (const response of [
    { status: "unknown", sequence: 1 },
    { status: "rejected", sequence: 0 },
    { status: "ok", sequence: 9, data: { dashboard_id: "id", version: 1, mode: "new" } },
    { status: "ok", sequence: 1, data: { dashboard_id: "id", version: 1, mode: "clone" } },
    { status: "invalid", sequence: 1, code: "arbitrary" },
    new Error("lost reply"),
  ]) {
    const execute = vi.fn(async () => {
      if (response instanceof Error) throw response;
      return response;
    });
    const { wrapper, navigate, refresh } = setup(state(), execute);
    await wrapper.get("#dashboard-name").setValue("Flight");
    await wrapper.get("#dashboard-new-form").trigger("submit");
    await flushPromises();
    await wrapper.setProps({ state: state() });
    await wrapper.get("#dashboard-creation-refresh").trigger("click");
    await flushPromises();
    await wrapper.get("#dashboard-new-form").trigger("submit");
    expect(execute).toHaveBeenCalledTimes(1);
    expect(navigate).not.toHaveBeenCalled();
    expect(refresh).toHaveBeenCalledOnce();
    expect(wrapper.get("#dashboard-new-submit").attributes("disabled")).toBeDefined();
  }
});
