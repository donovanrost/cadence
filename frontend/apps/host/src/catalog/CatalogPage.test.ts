import { flushPromises, mount } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import CatalogPage from "./CatalogPage.vue";
import { artifactFixture } from "./features/artifacts/fixtures.test-support";

const ready = () => ({
  page: "catalog_artifact_show",
  version: 1,
  status: "ready",
  data: artifactFixture(),
});
test("Catalog contains unavailable, incompatible and malformed snapshots and recovers on refresh", async () => {
  const refresh = vi.fn();
  const wrapper = mount(CatalogPage, {
    props: { page: "catalog_artifact_show", snapshot: null, execute: vi.fn(), refresh },
  });
  for (const snapshot of [
    null,
    {},
    { ...ready(), version: 2 },
    { ...ready(), page: "catalog_index" },
    { ...ready(), status: "unavailable" },
    { ...ready(), data: {} },
  ]) {
    await wrapper.setProps({ snapshot });
    expect(wrapper.find("#core-catalog-error").exists()).toBe(true);
    expect(wrapper.find("#catalog-artifact-reimport-button").exists()).toBe(false);
  }
  await wrapper.get("#core-catalog-retry").trigger("click");
  expect(refresh).toHaveBeenCalledOnce();
  await wrapper.setProps({ snapshot: ready() });
  expect(wrapper.find("#core-catalog-error").exists()).toBe(false);
  expect(wrapper.find("#catalog-artifact-download-link").exists()).toBe(true);
  wrapper.unmount();
});
test("reimport dispatches once while pending and reports sanitized failures", async () => {
  let reject!: (error: Error) => void;
  const execute = vi.fn(
    () =>
      new Promise<void>((_resolve, fail) => {
        reject = fail;
      }),
  );
  const wrapper = mount(CatalogPage, {
    props: { page: "catalog_artifact_show", snapshot: ready(), execute, refresh: vi.fn() },
  });
  await wrapper.get("#catalog-artifact-reimport-button").trigger("click");
  await wrapper.get("#catalog-artifact-reimport-button").trigger("click");
  expect(execute).toHaveBeenCalledExactlyOnceWith("reimport");
  expect(wrapper.find("#core-catalog-action-pending").exists()).toBe(true);
  reject(new Error("sensitive backend detail"));
  await flushPromises();
  expect(wrapper.find("#core-catalog-action-error").exists()).toBe(true);
  expect(wrapper.text()).not.toContain("sensitive backend detail");
  wrapper.unmount();
});
