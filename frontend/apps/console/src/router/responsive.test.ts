import { flushPromises, mount } from "@vue/test-utils";
import { defineComponent, h } from "vue";
import { describe, expect, it, vi } from "vite-plus/test";

type Listener = (event: { matches: boolean }) => void;
const listeners: Listener[] = [];
let matches = false;
vi.stubGlobal("matchMedia", () => ({
  get matches() {
    return matches;
  },
  addEventListener: (_: string, listener: Listener) => listeners.push(listener),
}));

const { responsive } = await import("./responsive.ts");

const Desktop = defineComponent({ render: () => h("p", "desktop") });
const Mobile = defineComponent({ render: () => h("p", "mobile") });

describe("responsive", () => {
  it("renders the desktop screen, then the mobile one when the viewport drops below 768", async () => {
    const Screen = responsive(
      () => Promise.resolve(Desktop),
      () => Promise.resolve(Mobile),
    );
    const wrapper = mount(Screen);
    await flushPromises();
    expect(wrapper.text()).toBe("desktop");
    matches = true;
    for (const listener of listeners) listener({ matches: true });
    await flushPromises();
    expect(wrapper.text()).toBe("mobile");
  });
});
