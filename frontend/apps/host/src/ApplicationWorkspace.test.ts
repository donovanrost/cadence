import { flushPromises, mount } from "@vue/test-utils";
import { defineComponent } from "vue";
import { beforeEach, describe, expect, it, vi } from "vite-plus/test";
import {
  assertFrontendApplicationCatalog,
  type FrontendApplicationCatalog,
} from "@cadence/plugin-sdk";
import { DemoHostService } from "../../../tools/demo-host-service";
import ApplicationWorkspace from "./ApplicationWorkspace.vue";
import { loadFrontendApplicationCatalog } from "./catalog-client";
import { createHttpHostBridge, type HttpHostBridge } from "./http-host-bridge";

vi.mock("./catalog-client", () => ({ loadFrontendApplicationCatalog: vi.fn() }));
vi.mock("./http-host-bridge", () => ({ createHttpHostBridge: vi.fn() }));

const RemoteBoundaryStub = defineComponent({
  emits: ["retry"],
  template:
    '<div id="remote-boundary-stub"><button id="retry-remote-stub" type="button" @click="$emit(\'retry\')"></button></div>',
});

type TestBridge = HttpHostBridge & {
  invalidate: ReturnType<typeof vi.fn>;
  subscribeMock: ReturnType<typeof vi.fn>;
  unsubscribe: ReturnType<typeof vi.fn>;
};

const workspaceCatalog = catalogFromDemo();

function catalogFromDemo(): FrontendApplicationCatalog {
  const response = new DemoHostService("development").handle({
    method: "GET",
    url: "/api/cadence/application-host/v1/catalog",
  });
  assertFrontendApplicationCatalog(response?.body);
  return response.body;
}

function testBridge(): TestBridge {
  const unsubscribe = vi.fn();
  const subscribe = vi.fn(() => unsubscribe);
  return {
    query: vi.fn(),
    execute: vi.fn(),
    subscribe,
    subscribeMock: subscribe,
    unsubscribe,
    invalidate: vi.fn(),
  } as unknown as TestBridge;
}

function useBridgeSequence(bridges: TestBridge[]): void {
  let bridgeIndex = 0;
  vi.mocked(createHttpHostBridge).mockImplementation(() => {
    const bridge = bridges[bridgeIndex];
    bridgeIndex += 1;
    if (!bridge) throw new Error("Unexpected bridge construction.");
    return bridge;
  });
}

async function mountWorkspace(bridges: TestBridge[]) {
  vi.mocked(loadFrontendApplicationCatalog).mockResolvedValue(workspaceCatalog);
  useBridgeSequence(bridges);
  const wrapper = mount(ApplicationWorkspace, {
    global: { stubs: { RemoteApplicationBoundary: RemoteBoundaryStub } },
  });
  await flushPromises();
  return wrapper;
}

beforeEach(() => {
  window.history.replaceState({}, "", "/applications");
  vi.mocked(loadFrontendApplicationCatalog).mockReset();
  vi.mocked(createHttpHostBridge).mockReset();
});

describe("ApplicationWorkspace bridge ownership", () => {
  it("invalidates the exact abandoned bridge before switching applications", async () => {
    const firstBridge = testBridge();
    const secondBridge = testBridge();
    const wrapper = await mountWorkspace([firstBridge, secondBridge]);

    expect(wrapper.find("#open-telemetry_decom").exists()).toBe(true);
    await wrapper.get("#open-contract_probe").trigger("click");

    expect(firstBridge.unsubscribe).toHaveBeenCalledTimes(1);
    expect(firstBridge.invalidate).toHaveBeenCalledTimes(1);
    expect(firstBridge.unsubscribe.mock.invocationCallOrder[0]).toBeLessThan(
      firstBridge.invalidate.mock.invocationCallOrder[0],
    );
    expect(secondBridge.subscribeMock).toHaveBeenCalledTimes(1);
    expect(wrapper.find("#open-contract_probe").classes()).toContain("active");

    wrapper.unmount();
    expect(secondBridge.unsubscribe).toHaveBeenCalledTimes(1);
    expect(secondBridge.invalidate).toHaveBeenCalledTimes(1);
  });

  it("invalidates the abandoned bridge before replacing a remote generation", async () => {
    const firstBridge = testBridge();
    const secondBridge = testBridge();
    const wrapper = await mountWorkspace([firstBridge, secondBridge]);

    await wrapper.get("#retry-remote-stub").trigger("click");

    expect(firstBridge.unsubscribe).toHaveBeenCalledTimes(1);
    expect(firstBridge.invalidate).toHaveBeenCalledTimes(1);
    expect(firstBridge.unsubscribe.mock.invocationCallOrder[0]).toBeLessThan(
      firstBridge.invalidate.mock.invocationCallOrder[0],
    );
    expect(vi.mocked(createHttpHostBridge)).toHaveBeenCalledTimes(2);
    expect(secondBridge.subscribeMock).toHaveBeenCalledTimes(1);

    wrapper.unmount();
    expect(secondBridge.invalidate).toHaveBeenCalledTimes(1);
  });

  it("invalidates the current bridge and unsubscribes on unmount", async () => {
    const bridge = testBridge();
    const wrapper = await mountWorkspace([bridge]);

    wrapper.unmount();

    expect(bridge.unsubscribe).toHaveBeenCalledTimes(1);
    expect(bridge.invalidate).toHaveBeenCalledTimes(1);
    expect(bridge.unsubscribe.mock.invocationCallOrder[0]).toBeLessThan(
      bridge.invalidate.mock.invocationCallOrder[0],
    );
  });
});
