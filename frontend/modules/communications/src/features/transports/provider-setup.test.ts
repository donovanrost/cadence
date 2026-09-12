import { mount, flushPromises } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import TransportCreation from "./TransportCreation.vue";
import { admitValidation } from "./validation-receipt";
import { providerTransportForm, providerValidation } from "./provider-setup.test-support";
import type { FormInput } from "../../shared/form-workflow.contracts";

const input = (): FormInput => ({
  transport: {
    display_name: "Downlink",
    origin: "provider_managed",
    transport_kind: "tcp_socket",
    mission_provider_id: "provider-1",
    mission_provider_version: "2",
    service_profile_id: "provider-1-service-v3",
    delivery_profile_id: "provider-1-delivery-v7",
  },
});

test("provider choices, partial preview and exact-version save stay inside the transport feature", async () => {
  const port = {
    execute: vi.fn(async (action: string, draft: FormInput) =>
      action === "validate"
        ? providerValidation(draft)
        : { navigation: { href: "/missions/mission-1/comms/transports/saved" } },
    ),
    navigate: vi.fn(),
  };
  const wrapper = mount(TransportCreation, {
    props: { ...providerTransportForm(), port, context: { missionId: "mission-1" } },
  });
  try {
    await wrapper.get("#transport-origin").setValue("provider_managed");
    await flushPromises();
    expect(wrapper.get("#transport-service-profile").attributes("disabled")).toBeDefined();
    await wrapper.get("#transport-provider").setValue("provider-1");
    await flushPromises();
    expect(wrapper.get("#transport-service-profile").text()).toContain("Realtime telemetry · v3");
    expect(wrapper.get("#create-transport-button").attributes("disabled")).toBeDefined();
    await wrapper.get("#transport-service-profile").setValue("provider-1-service-v3");
    await flushPromises();
    expect(wrapper.get("#transport-delivery-profile").text()).toContain("Primary ingress · v7");
    await wrapper.get("#transport-delivery-profile").setValue("provider-1-delivery-v7");
    await flushPromises();
    expect(wrapper.get("#configuration").text()).toContain("1115");
    expect(wrapper.get("#configuration").findAll("input,select")).toHaveLength(0);
    expect(wrapper.get("#create-transport-button").attributes("disabled")).toBeDefined();
    const node = wrapper.get("#transport-display-name").element;
    await wrapper.get("#transport-display-name").setValue("Downlink");
    await flushPromises();
    expect(wrapper.get("#transport-display-name").element).toBe(node);
    expect(wrapper.get("#create-transport-button").attributes("disabled")).toBeUndefined();
    await wrapper.get("#transport-form").trigger("submit");
    await flushPromises();
    expect(port.execute).toHaveBeenLastCalledWith("save", input());
    expect(port.navigate).toHaveBeenCalledExactlyOnceWith(
      "/missions/mission-1/comms/transports/saved",
    );
  } finally {
    wrapper.unmount();
  }
});

test("provider changes clear dependent selections and cannot admit an obsolete choice response", async () => {
  let finish!: (value: unknown) => void;
  const port = {
    execute: vi.fn(async (_action: string, draft: FormInput): Promise<unknown> => {
      if (draft.transport.mission_provider_id === "provider-1")
        return new Promise((resolve) => {
          finish = resolve;
        });
      return providerValidation(draft);
    }),
    navigate: vi.fn(),
  };
  const wrapper = mount(TransportCreation, {
    props: { ...providerTransportForm(), port, context: { missionId: "mission-1" } },
  });
  try {
    await wrapper.get("#transport-origin").setValue("provider_managed");
    await flushPromises();
    await wrapper.get("#transport-provider").setValue("provider-1");
    const obsolete = port.execute.mock.calls.at(-1)![1];
    await wrapper.get("#transport-provider").setValue("provider-2");
    finish(providerValidation(obsolete));
    await flushPromises();
    expect(wrapper.find('option[value="provider-1-service-v3"]').exists()).toBe(false);
    await wrapper.get("#transport-service-profile").setValue("provider-2-service-v3");
    await flushPromises();
    await wrapper.get("#transport-delivery-profile").setValue("provider-2-delivery-v7");
    await flushPromises();
    await wrapper.get("#transport-service-profile").setValue("");
    await flushPromises();
    expect(port.execute.mock.calls.at(-1)![1].transport.delivery_profile_id).toBe("");
    expect(wrapper.get("#configuration").text()).not.toContain("1115");
    expect(wrapper.get("#create-transport-button").attributes("disabled")).toBeDefined();
  } finally {
    wrapper.unmount();
  }
});

test("provider receipt admission rejects forged identity, choices, versions and previews", () => {
  const draft = input();
  for (const mutate of [
    (r: ReturnType<typeof providerValidation>) => {
      r.provider_setup.version = 2;
    },
    (r: ReturnType<typeof providerValidation>) => {
      r.provider_setup.provider_version = "3";
    },
    (r: ReturnType<typeof providerValidation>) => {
      r.provider_setup.provider_id = "other";
    },
    (r: ReturnType<typeof providerValidation>) => {
      r.provider_setup.deliveries = [];
    },
    (r: ReturnType<typeof providerValidation>) => {
      r.provider_setup.services.push(r.provider_setup.services[0]);
    },
    (r: ReturnType<typeof providerValidation>) => {
      r.provider_setup.configuration[0].value = "other-endpoint";
    },
    (r: ReturnType<typeof providerValidation>) => {
      r.provider_setup.configuration[0].label = "secret";
    },
  ]) {
    const receipt = providerValidation(draft);
    mutate(receipt);
    expect(() => admitValidation(receipt, draft)).toThrow();
  }
});
