import { expect, test, vi } from "vite-plus/test";
import { flushPromises, mount } from "@vue/test-utils";
import CadenceClipboardButton from "./CadenceClipboardButton.vue";

test("a pending clipboard response cannot schedule feedback after unmount", async () => {
  let complete: () => void = () => {
    throw new Error("Clipboard request was not started");
  };
  const pending = new Promise<void>((resolve) => {
    complete = resolve;
  });
  const clipboard = vi.spyOn(navigator.clipboard, "writeText").mockReturnValue(pending);
  const timers = vi.spyOn(globalThis, "setTimeout");
  const wrapper = mount(CadenceClipboardButton, {
    props: { button_id: "copy-link", icon: "hero-link", clipboard_text: "/missions" },
  });
  try {
    await wrapper.get("button").trigger("click");
    expect(clipboard).toHaveBeenCalledOnce();
    wrapper.unmount();
    timers.mockClear();
    complete();
    await flushPromises();
    expect(timers.mock.calls.some(([, delay]) => delay === 1500)).toBe(false);
  } finally {
    wrapper.unmount();
    clipboard.mockRestore();
    timers.mockRestore();
  }
});
