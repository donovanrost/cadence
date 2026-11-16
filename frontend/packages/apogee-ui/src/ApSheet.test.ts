import { mount } from "@vue/test-utils";
import { nextTick } from "vue";
import { describe, expect, it } from "vite-plus/test";
import ApSheet from "./ApSheet.vue";

describe("ApSheet", () => {
  function mountSheet(initialFocus?: string) {
    const opener = document.createElement("button");
    document.body.append(opener);
    const wrapper = mount(ApSheet, {
      attachTo: document.body,
      props: { title: "Send back", ...(initialFocus ? { initialFocus } : {}) },
      slots: {
        default: '<textarea aria-label="Why"></textarea>',
        footer: "<button>Cancel</button><button>Send back</button>",
      },
    });
    // The exposed open()/close(), typed here: the .vue default export reads as `error` to oxlint.
    const sheet = wrapper.vm as { open: () => void; close: () => void };
    return { wrapper, sheet, opener };
  }

  it("is named by its title, focuses the first footer button, and returns focus on close", async () => {
    const { wrapper, sheet, opener } = mountSheet();
    const dialog = wrapper.get("dialog");
    const heading = wrapper.get("h2");
    expect(dialog.attributes("aria-labelledby")).toBe(heading.attributes("id"));
    expect(heading.text()).toBe("Send back");

    opener.focus();
    sheet.open();
    await nextTick();
    expect(dialog.element.open).toBe(true);
    expect(document.activeElement?.textContent).toBe("Cancel");

    sheet.close();
    await nextTick();
    expect(document.activeElement).toBe(opener);
    expect(wrapper.emitted("closed")).toHaveLength(1);
    wrapper.unmount();
    opener.remove();
  });

  it("focuses the caller's initialFocus target instead", async () => {
    const { wrapper, sheet, opener } = mountSheet("textarea");
    sheet.open();
    await nextTick();
    expect(document.activeElement?.tagName).toBe("TEXTAREA");
    wrapper.unmount();
    opener.remove();
  });

  it("opens a side sheet without a modal and closes it on Escape", async () => {
    const wrapper = mount(ApSheet, {
      attachTo: document.body,
      props: { title: "Widget", placement: "side" },
      slots: { default: "<input aria-label='Name' />" },
    });
    const sheet = wrapper.vm as { open: () => void; close: () => void };
    sheet.open();
    await nextTick();
    const dialog = wrapper.get("dialog");
    expect(dialog.element.open).toBe(true);
    expect(dialog.attributes("aria-modal")).toBeUndefined();
    await dialog.trigger("keydown", { key: "Escape" });
    expect(dialog.element.open).toBe(false);
    wrapper.unmount();
  });

  it("moves focus back into an open side sheet when its opener is used again (ux a11y A3)", async () => {
    const opener = document.createElement("button");
    const elsewhere = document.createElement("button");
    document.body.append(opener, elsewhere);
    const wrapper = mount(ApSheet, {
      attachTo: document.body,
      props: { title: "Widget", placement: "side", initialFocus: "input" },
      slots: { default: "<input aria-label='Name' />" },
    });
    const sheet = wrapper.vm as { open: () => void; close: () => void };
    const input = wrapper.get("input").element;
    opener.focus();
    sheet.open();
    await nextTick();
    expect(document.activeElement).toBe(input);
    // Tab may leave a side sheet for the page; using the opener again brings focus back in.
    elsewhere.focus();
    sheet.open();
    await nextTick();
    expect(document.activeElement).toBe(input);
    // Closing still returns focus to the first opener.
    sheet.close();
    await nextTick();
    expect(document.activeElement).toBe(opener);
    wrapper.unmount();
    opener.remove();
    elsewhere.remove();
  });

  it("refuses Escape when not dismissible, but still closes from the caller", async () => {
    const wrapper = mount(ApSheet, {
      attachTo: document.body,
      props: { title: "Your token", dismissible: false },
      slots: { default: "<p>secret</p>", footer: "<button>Done</button>" },
    });
    const sheet = wrapper.vm as { open: () => void; close: () => void };
    sheet.open();
    await nextTick();
    const dialog = wrapper.get("dialog");
    const cancel = new Event("cancel", { cancelable: true });
    dialog.element.dispatchEvent(cancel);
    expect(cancel.defaultPrevented).toBe(true);
    sheet.close();
    await nextTick();
    expect(dialog.element.open).toBe(false);
    wrapper.unmount();
  });
});
