import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { defineComponent, h } from "vue";
import { missionId } from "@/api/index.ts";
import { answerByPath, configState } from "./fixtures.ts";
import { useCanStage } from "./useConfigState.ts";

vi.mock("@/live", () => ({ useMissionInvalidation: () => undefined }));
afterEach(() => vi.unstubAllGlobals());

/** The gate every #1160 row 1 screen reads: the server's config.stage, never a role. */
const Probe = defineComponent({
  setup() {
    const canStage = useCanStage(missionId("m-1"));
    return () => h("p", canStage.value ? "may stage" : "may not stage");
  },
});

describe("useCanStage (#1160 row 1)", () => {
  it("is the server's config.stage: an operator who holds it may stage", async () => {
    vi.stubGlobal("fetch", answerByPath({ "/missions/m-1/config": configState(["config.stage"]) }));
    const w = mount(Probe);
    await flushPromises();
    expect(w.text()).toBe("may stage");
    w.unmount();
  });

  it("is false without config.stage, and while the config state is still being read", async () => {
    vi.stubGlobal("fetch", answerByPath({ "/missions/m-1/config": configState(["config.apply"]) }));
    const w = mount(Probe);
    expect(w.text()).toBe("may not stage");
    await flushPromises();
    expect(w.text()).toBe("may not stage");
    w.unmount();
  });
});
