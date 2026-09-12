import { required } from "../../../../../test-support/required";
import { mount, flushPromises } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import Adapter from "./MissionTransportCreation.vue";
import { transportFormPayload } from "./fixtures.test-support";
import { setupPages } from "./setup.contribution";
const context = { organizationId: "org-1", missionId: "mission-1" };
function envelope() {
  return {
    phase: "editing",
    model: {
      navigation: { fallback_href: "/missions/mission-1/comms/transports/new", breadcrumbs: [] },
      data: transportFormPayload(),
    },
  };
}
function validation() {
  return {
    status: "ok",
    data: {
      result: {
        valid: true,
        transport_review: { origin: "direct", endpoint: "tcp://localhost:5000" },
      },
    },
  };
}
test("same-instance refresh preserves the mounted draft, validation, and action port", async () => {
  const registration = setupPages[0];
  const port = { execute: vi.fn().mockResolvedValue(validation()), navigate: vi.fn() };
  const wrapper = mount(Adapter, {
    props: { ...required(registration).read(envelope(), context), port } as never,
  });
  try {
    const input = wrapper.get("#transport-display-name").element as HTMLInputElement;
    await wrapper.get("#transport-display-name").setValue("Draft");
    await flushPromises();
    const replacementPort = { execute: vi.fn(), navigate: vi.fn() };
    await wrapper.setProps({
      ...required(registration).read(envelope(), context),
      port: replacementPort,
    } as never);
    expect(wrapper.get("#transport-display-name").element).toBe(input);
    expect(input.value).toBe("Draft");
    port.execute.mockResolvedValue({
      status: "ok",
      data: { result: { navigation: { href: "/missions/mission-1/comms/transports/t1" } } },
    });
    await wrapper.get("#transport-form").trigger("submit");
    await flushPromises();
    expect(port.execute).toHaveBeenLastCalledWith("save", expect.any(Object));
    expect(replacementPort.execute).not.toHaveBeenCalled();
    expect(port.navigate).toHaveBeenCalledWith("/missions/mission-1/comms/transports/t1");
  } finally {
    wrapper.unmount();
  }
});
test("uncertain saves remain locked across refresh, and confirmed refresh hides the consumed form", async () => {
  const registration = setupPages[0];
  const port = {
    execute: vi.fn().mockResolvedValueOnce(validation()).mockResolvedValue({ status: "unknown" }),
    navigate: vi.fn(),
  };
  const wrapper = mount(Adapter, {
    props: { ...required(registration).read(envelope(), context), port } as never,
  });
  try {
    await wrapper.get("#transport-display-name").setValue("Uncertain draft");
    await flushPromises();
    await wrapper.get("#transport-form").trigger("submit");
    await flushPromises();
    await wrapper.setProps({
      ...required(registration).read({ ...envelope(), phase: "submitted" }, context),
    } as never);
    expect((wrapper.get("#transport-display-name").element as HTMLInputElement).value).toBe(
      "Uncertain draft",
    );
    expect(wrapper.get("fieldset.contents").attributes("disabled")).toBeDefined();
    expect(wrapper.find("#comms-setup-outcome").exists()).toBe(true);
    await wrapper.get("#transport-form").trigger("submit");
    await flushPromises();
    expect(port.execute).toHaveBeenCalledTimes(2);
    expect(port.navigate).not.toHaveBeenCalled();
    await wrapper.setProps({
      ...required(registration).read({ ...envelope(), phase: "completed" }, context),
    } as never);
    expect(wrapper.find("#transport-form").exists()).toBe(false);
    expect(wrapper.get("#comms-setup-review-records").attributes("href")).toContain(
      "/missions/mission-1/comms/",
    );
  } finally {
    wrapper.unmount();
  }
});
test("setup contribution rejects malformed phases and foreign creation resources", () => {
  expect(() => required(setupPages[0]).read({ ...envelope(), phase: "retry" }, context)).toThrow();
  expect(() =>
    required(setupPages[0]).read(envelope(), { ...context, resourceId: "foreign" }),
  ).toThrow();
});
