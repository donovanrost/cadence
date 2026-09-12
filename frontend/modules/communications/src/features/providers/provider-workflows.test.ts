import { containing } from "../../../../../test-support/matchers";
import { mount, flushPromises } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import ProviderCreation from "./ProviderCreation.vue";
import ProviderDetail from "./ProviderDetail.vue";
import { readForm } from "./form-validation";
import { readDetail } from "./read-validation";
import { providerNewSurface, providerDetailSurface } from "./surface-fixtures.test-support";
import { FormActionFailure } from "../../shared/form-workflow.contracts";
const context = { missionId: "mission-1" };
const receipt = { result: { provider_id: "provider-1", version: 2, display_name: "Simulator" } };

test("creation updates the selected account summary, preserves typing and sends exact binding versions once", async () => {
  let finish!: (value: unknown) => void;
  const port = {
    execute: vi.fn(
      () =>
        new Promise((resolve) => {
          finish = resolve;
        }),
    ),
    query: vi.fn(),
    navigate: vi.fn(),
  };
  const wrapper = mount(ProviderCreation, {
    props: { model: readForm(providerNewSurface(), context), context, port },
  });
  try {
    const input = wrapper.get("#provider_display_name").element;
    await wrapper.get("#provider_display_name").setValue("Flight provider");
    await wrapper.get("#provider_provider_account_grant_id").setValue("grant-2");
    expect(wrapper.get("#mission-provider-account-summary").text()).toContain("Ground Network 2");
    expect(wrapper.get("#provider_display_name").element).toBe(input);
    await wrapper.get("#mission-provider-form").trigger("submit");
    await wrapper.get("#mission-provider-form").trigger("submit");
    expect(port.execute).toHaveBeenCalledTimes(1);
    expect(port.execute).toHaveBeenCalledWith("create_provider", {
      provider: containing({
        display_name: "Flight provider",
        provider_account_grant_id: "grant-2",
        provider_account_id: "account-2",
        provider_account_version: "4",
        provider_account_grant_version: "2",
      }),
    });
    expect(wrapper.get("fieldset.contents").attributes("disabled")).toBeDefined();
    finish(receipt);
    await flushPromises();
    expect(port.navigate).toHaveBeenCalledExactlyOnceWith(
      "/missions/mission-1/comms/providers/provider-1",
    );
    await wrapper.get("#mission-provider-form").trigger("submit");
    expect(port.execute).toHaveBeenCalledTimes(1);
  } finally {
    wrapper.unmount();
  }
});
test("creation validates bounded policy inputs and preserves its draft on known rejection", async () => {
  const port = {
    execute: vi.fn().mockRejectedValue(new FormActionFailure("rejected")),
    query: vi.fn(),
    navigate: vi.fn(),
  };
  const wrapper = mount(ProviderCreation, {
    props: { model: readForm(providerNewSurface(), context), context, port },
  });
  try {
    await wrapper.get("#provider_policy_mode").setValue("bounded_automatic");
    expect(wrapper.get("#create-mission-provider-button").attributes("disabled")).toBeDefined();
    await wrapper.get("#provider_minimum_retained_duration_seconds").setValue("60");
    await wrapper.get("#mission-provider-form").trigger("submit");
    await flushPromises();
    expect(wrapper.get("#provider_minimum_retained_duration_seconds").element).toHaveProperty(
      "value",
      "60",
    );
    expect(wrapper.get("#provider-creation-status").text()).toContain("rejected");
    expect(wrapper.get("#create-mission-provider-button").attributes("disabled")).toBeUndefined();
  } finally {
    wrapper.unmount();
  }
});
test.each(["unknown", "malformed"])(
  "creation contains %s outcomes without blind resubmission",
  async (outcome) => {
    const execute =
      outcome === "unknown"
        ? vi.fn().mockRejectedValue(new Error("private data"))
        : vi.fn().mockResolvedValue({});
    const wrapper = mount(ProviderCreation, {
      props: {
        model: readForm(providerNewSurface(), context),
        context,
        port: { execute, query: vi.fn(), navigate: vi.fn() },
      },
    });
    try {
      await wrapper.get("#mission-provider-form").trigger("submit");
      await flushPromises();
      expect(wrapper.get("#provider-creation-status").text()).not.toContain("private data");
      expect(wrapper.find("#check-provider-records").exists()).toBe(true);
      await wrapper.get("#mission-provider-form").trigger("submit");
      expect(execute).toHaveBeenCalledTimes(1);
    } finally {
      wrapper.unmount();
    }
  },
);
test("detail actions disable pending controls and refresh through the same admitted provider contract", async () => {
  let finish!: (value: unknown) => void;
  const port = {
    execute: vi.fn(
      () =>
        new Promise((resolve) => {
          finish = resolve;
        }),
    ),
    query: vi.fn().mockResolvedValue(providerDetailSurface(2)),
    navigate: vi.fn(),
  };
  const wrapper = mount(ProviderDetail, {
    props: { model: readDetail(providerDetailSurface(), context), context, port },
  });
  try {
    await wrapper.get("#sync-provider-button").trigger("click");
    expect(port.execute).toHaveBeenCalledExactlyOnceWith("sync_provider", {
      provider_id: "provider-1",
    });
    expect(wrapper.get("#validate-provider-button").attributes("disabled")).toBeDefined();
    finish(receipt);
    await flushPromises();
    expect(port.query).toHaveBeenCalledTimes(1);
    expect(wrapper.find("#version-2").exists()).toBe(true);
    expect(wrapper.get("#sync-provider-button").attributes("disabled")).toBeUndefined();
  } finally {
    wrapper.unmount();
  }
});
test("a failed refresh retains the page and offers only read-only recovery before another action", async () => {
  const port = {
    execute: vi.fn().mockResolvedValue(receipt),
    query: vi
      .fn()
      .mockRejectedValueOnce(new FormActionFailure("rejected"))
      .mockResolvedValueOnce(providerDetailSurface(1))
      .mockResolvedValue(providerDetailSurface(2)),
    navigate: vi.fn(),
  };
  const wrapper = mount(ProviderDetail, {
    props: { model: readDetail(providerDetailSurface(), context), context, port },
  });
  try {
    await wrapper.get("#validate-provider-button").trigger("click");
    await flushPromises();
    expect(wrapper.find("#comms-provider-show-page").exists()).toBe(true);
    expect(wrapper.get("#validate-provider-button").attributes("disabled")).toBeDefined();
    await wrapper.get("#refresh-provider-state").trigger("click");
    await flushPromises();
    expect(port.execute).toHaveBeenCalledTimes(1);
    expect(port.query).toHaveBeenCalledTimes(2);
    expect(wrapper.get("#validate-provider-button").attributes("disabled")).toBeDefined();
    await wrapper.get("#refresh-provider-state").trigger("click");
    await flushPromises();
    expect(port.execute).toHaveBeenCalledTimes(1);
    expect(port.query).toHaveBeenCalledTimes(3);
    expect(wrapper.find("#version-2").exists()).toBe(true);
  } finally {
    wrapper.unmount();
  }
});
test("confirmed archival returns to the directory instead of querying a now-unavailable detail", async () => {
  const originalConfirm = Object.getOwnPropertyDescriptor(window, "confirm");
  Object.defineProperty(window, "confirm", {
    configurable: true,
    value: vi.fn().mockReturnValueOnce(false).mockReturnValue(true),
  });
  const port = { execute: vi.fn().mockResolvedValue(receipt), query: vi.fn(), navigate: vi.fn() };
  const wrapper = mount(ProviderDetail, {
    props: { model: readDetail(providerDetailSurface(), context), context, port },
  });
  try {
    await wrapper.get("#archive-provider-button").trigger("click");
    expect(port.execute).not.toHaveBeenCalled();
    await wrapper.get("#archive-provider-button").trigger("click");
    await flushPromises();
    expect(port.execute).toHaveBeenCalledExactlyOnceWith("archive_provider", {
      provider_id: "provider-1",
    });
    expect(port.navigate).toHaveBeenCalledExactlyOnceWith("/missions/mission-1/comms/providers");
    expect(port.query).not.toHaveBeenCalled();
    expect(wrapper.get("#archive-provider-button").attributes("disabled")).toBeDefined();
  } finally {
    wrapper.unmount();
    if (originalConfirm) Object.defineProperty(window, "confirm", originalConfirm);
    else Reflect.deleteProperty(window, "confirm");
  }
});
test("unmounted creation cannot navigate and unmounted detail cannot start a refresh", async () => {
  for (const component of [ProviderCreation, ProviderDetail]) {
    let finish!: (value: unknown) => void;
    const port = {
      execute: vi.fn(
        () =>
          new Promise((resolve) => {
            finish = resolve;
          }),
      ),
      query: vi.fn(),
      navigate: vi.fn(),
    };
    const wrapper =
      component === ProviderCreation
        ? mount(ProviderCreation, {
            props: { model: readForm(providerNewSurface(), context), context, port },
          })
        : mount(ProviderDetail, {
            props: { model: readDetail(providerDetailSurface(), context), context, port },
          });
    if (component === ProviderCreation)
      await wrapper.get("#mission-provider-form").trigger("submit");
    else await wrapper.get("#sync-provider-button").trigger("click");
    wrapper.unmount();
    finish(receipt);
    await flushPromises();
    expect(port.navigate).not.toHaveBeenCalled();
    expect(port.query).not.toHaveBeenCalled();
  }
});
