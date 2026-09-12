import { flushPromises, mount } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import CommandAuthoringPage from "./CommandAuthoringPage.vue";
import { readAuthoringContribution, type AuthoringPrerequisite } from "./contracts";
import { pageFixture } from "./fixtures.test-support";

function prerequisite(): AuthoringPrerequisite {
  const { catalog } = pageFixture();
  return {
    state: "command_model_required",
    version: 1,
    context: catalog.context,
    actor_id: catalog.actor_id,
  };
}

test("prerequisite admission rejects foreign context, unknown versions and mixed catalog data", () => {
  const page = prerequisite();
  expect(readAuthoringContribution(page, page.context)).toEqual(page);
  for (const bad of [
    { ...page, version: 2 },
    { ...page, state: "unknown" },
    { ...page, actor_id: "" },
    { ...page, catalog: pageFixture().catalog },
    { ...page, context: { ...page.context, missionId: "foreign" } },
    { ...page, context: { ...page.context, organizationId: "foreign" } },
  ])
    expect(() => readAuthoringContribution(bad, page.context)).toThrow();
});

test("missing model explains setup, performs only a refresh, and recovers to authoring", async () => {
  const execute = vi.fn();
  let resolve!: () => void;
  const refresh = vi.fn(
    () =>
      new Promise<void>((done) => {
        resolve = done;
      }),
  );
  const wrapper = mount(CommandAuthoringPage, {
    props: {
      page: prerequisite(),
      port: { execute, navigate: vi.fn() },
      readPort: { read: vi.fn() },
      refresh,
    },
  });
  expect(wrapper.get("#command-authoring-prerequisite").text()).toContain("approved mission model");
  expect(wrapper.find("#command-authoring-form").exists()).toBe(false);
  expect(wrapper.find("#command-authoring-create").exists()).toBe(false);
  expect(wrapper.get("#command-authoring-prerequisite-monitor").attributes("href")).toBe(
    `/missions/${encodeURIComponent(prerequisite().context.missionId)}/ops/commands`,
  );
  await wrapper.get("#command-authoring-prerequisite-refresh").trigger("click");
  expect(
    wrapper.get("#command-authoring-prerequisite-refresh").attributes("disabled"),
  ).toBeDefined();
  expect(refresh).toHaveBeenCalledTimes(1);
  resolve();
  await flushPromises();
  expect(execute).not.toHaveBeenCalled();
  await wrapper.setProps({ page: pageFixture() });
  expect(wrapper.find("#command-authoring-prerequisite").exists()).toBe(false);
  expect(wrapper.find("#command-authoring-form").exists()).toBe(true);
  wrapper.unmount();
});

test("failed refresh preserves setup guidance and does not expose private errors", async () => {
  const wrapper = mount(CommandAuthoringPage, {
    props: {
      page: prerequisite(),
      port: { execute: vi.fn(), navigate: vi.fn() },
      readPort: { read: vi.fn() },
      refresh: vi.fn().mockRejectedValue(Error("private backend error")),
    },
  });
  await wrapper.get("#command-authoring-prerequisite-refresh").trigger("click");
  await flushPromises();
  expect(wrapper.get('[role="status"]').text()).toContain("could not be checked");
  expect(wrapper.text()).not.toContain("private backend error");
  expect(
    wrapper.get("#command-authoring-prerequisite-refresh").attributes("disabled"),
  ).toBeUndefined();
  wrapper.unmount();
});
