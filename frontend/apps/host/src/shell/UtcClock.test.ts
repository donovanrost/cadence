import { mount } from "@vue/test-utils";
import { it, expect, vi } from "vite-plus/test";
import UtcClock from "./UtcClock.vue";
it("updates UTC time and releases its timer on unmount", async () => {
  vi.useFakeTimers();
  vi.setSystemTime(new Date("2026-09-05T23:59:59Z"));
  const clearIntervalSpy = vi.spyOn(globalThis, "clearInterval");
  const wrapper = mount(UtcClock);
  try {
    await wrapper.vm.$nextTick();
    expect(wrapper.get('[role="timer"]').text()).toBe("23:59:59 UTC");
    await vi.advanceTimersByTimeAsync(1000);
    expect(wrapper.text()).toBe("00:00:00 UTC");
    expect(wrapper.attributes("aria-live")).toBe("off");
    wrapper.unmount();
    expect(clearIntervalSpy).toHaveBeenCalledOnce();
  } finally {
    clearIntervalSpy.mockRestore();
    vi.useRealTimers();
  }
});
