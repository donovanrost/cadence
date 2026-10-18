import { afterEach, expect, test, vi } from "vite-plus/test";
import { mount, flushPromises } from "@vue/test-utils";
import CadenceClipboardButton from "./CadenceClipboardButton.vue";
let app: ReturnType<typeof mount>;
afterEach(() => {
  app?.unmount();
  vi.restoreAllMocks();
  vi.useRealTimers();
});
test("retains caller IDs, native button, URL resolution and copy feedback", async () => {
  vi.useFakeTimers();
  const write = vi.spyOn(navigator.clipboard, "writeText").mockResolvedValue();
  app = mount(CadenceClipboardButton, {
    props: {
      button_id: "copy-link",
      clipboard_text: "/missions/flight",
      icon: "hero-link",
      label: "Copy link",
      data_attrs: { "data-evidence": "caller" },
    },
  });
  const button = app.get("#copy-link").element;
  await app.get("#copy-link").trigger("click");
  await flushPromises();
  expect(write).toHaveBeenCalledWith(
    new URL("/missions/flight", window.location.origin).toString(),
  );
  expect(app.get("#copy-link").attributes("data-evidence")).toBe("caller");
  expect(app.get("#copy-link").attributes("data-clipboard-copied")).toBe("true");
  await app.setProps({ label: "Copy again" });
  expect(app.get("#copy-link").element).toBe(button);
  app.unmount();
  await vi.runAllTimersAsync();
});

test("raw text mode preserves hashes, punctuation and empty values without URL conversion", async () => {
  const write = vi.spyOn(navigator.clipboard, "writeText").mockResolvedValue();
  app = mount(CadenceClipboardButton, {
    props: {
      button_id: "copy-id",
      clipboard_text: "spacecraft_runtime:craft/a?b=1#fragment",
      copy_as: "text",
      icon: "hero-clipboard-document",
    },
  });
  await app.get("#copy-id").trigger("click");
  await flushPromises();
  expect(write).toHaveBeenLastCalledWith("spacecraft_runtime:craft/a?b=1#fragment");
  await app.setProps({ clipboard_text: "" });
  await app.get("#copy-id").trigger("click");
  await flushPromises();
  expect(write).toHaveBeenLastCalledWith("");
});
