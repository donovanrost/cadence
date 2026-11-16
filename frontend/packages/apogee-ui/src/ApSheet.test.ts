import { mount } from "@vue/test-utils";
import { nextTick } from "vue";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import ApSheet from "./ApSheet.vue";

afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

describe("ApSheet", () => {
  function mountSheet(initialFocus?: string, extra: Record<string, unknown> = {}) {
    const opener = document.createElement("button");
    document.body.append(opener);
    const wrapper = mount(ApSheet, {
      attachTo: document.body,
      props: { title: "Send back", ...(initialFocus ? { initialFocus } : {}), ...extra },
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

  it("is modal on a phone even as a side sheet, with a Close ✕ (design-language §9)", async () => {
    vi.stubGlobal("matchMedia", (query: string) => ({ matches: query.includes("max-width") }));
    const showModal = vi.spyOn(HTMLDialogElement.prototype, "showModal");
    const wrapper = mount(ApSheet, {
      attachTo: document.body,
      props: { title: "Widget", placement: "side", initialFocus: "input" },
      slots: { default: "<input aria-label='Name' />" },
    });
    const sheet = wrapper.vm as { open: () => void; close: () => void };
    sheet.open();
    await nextTick();
    const dialog = wrapper.get("dialog");
    // showModal: the page behind is inert, so focus is trapped (a11y A3 at this width).
    expect(showModal).toHaveBeenCalledOnce();
    expect(dialog.attributes("aria-modal")).toBe("true");
    await wrapper.get('button[aria-label="Close"]').trigger("click");
    expect(dialog.element.open).toBe(false);
    wrapper.unmount();
  });

  it("stays non-modal beside the page on a desktop", async () => {
    vi.stubGlobal("matchMedia", () => ({ matches: false }));
    const showModal = vi.spyOn(HTMLDialogElement.prototype, "showModal");
    const wrapper = mount(ApSheet, {
      attachTo: document.body,
      props: { title: "Widget", placement: "side" },
      slots: { default: "<input aria-label='Name' />" },
    });
    (wrapper.vm as { open: () => void }).open();
    await nextTick();
    expect(showModal).not.toHaveBeenCalled();
    expect(wrapper.get("dialog").attributes("aria-modal")).toBeUndefined();
    wrapper.unmount();
  });

  it("gives a sheet with no footer a Close ✕ at every width, and opens on it (a11y A1, A4)", async () => {
    vi.stubGlobal("matchMedia", () => ({ matches: false }));
    const wrapper = mount(ApSheet, {
      attachTo: document.body,
      props: { title: "History" },
      slots: { default: "<p>Switched by Mira</p>" },
    });
    (wrapper.vm as { open: () => void }).open();
    await nextTick();
    const close = wrapper.get('button[aria-label="Close"]');
    expect(close.classes()).not.toContain("hidden");
    expect(document.activeElement).toBe(close.element);
    wrapper.unmount();
  });

  it("keeps the ✕ to phones when the sheet has a footer", () => {
    const wrapper = mount(ApSheet, {
      props: { title: "Send back" },
      slots: { footer: "<button>Cancel</button>" },
    });
    expect(wrapper.get('button[aria-label="Close"]').classes()).toContain("hidden");
    wrapper.unmount();
  });

  it("offers no Close ✕ on a sheet only its caller may close", () => {
    const wrapper = mount(ApSheet, { props: { title: "Your token", dismissible: false } });
    expect(wrapper.find('button[aria-label="Close"]').exists()).toBe(false);
    wrapper.unmount();
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

  describe("A5: focus on close when the opener is gone", () => {
    it("goes to returnFocus (an element or a function), evaluated at close", async () => {
      const line = document.createElement("p");
      line.tabIndex = -1;
      document.body.append(line);
      const { wrapper, sheet, opener } = mountSheet(undefined, { returnFocus: () => line });
      opener.focus();
      sheet.open();
      await nextTick();
      opener.remove();
      sheet.close();
      await nextTick();
      expect(document.activeElement).toBe(line);
      wrapper.unmount();
      line.remove();
    });

    it("without returnFocus, goes to the page's main heading (tabindex -1), never <body>", async () => {
      const main = document.createElement("main");
      main.innerHTML = "<h1>Now</h1>";
      document.body.append(main);
      const { wrapper, sheet, opener } = mountSheet();
      opener.focus();
      sheet.open();
      await nextTick();
      opener.remove();
      sheet.close();
      await nextTick();
      expect(document.activeElement?.textContent).toBe("Now");
      expect(document.activeElement?.getAttribute("tabindex")).toBe("-1");
      wrapper.unmount();
      main.remove();
    });

    it("an opener still there gets focus back, whatever returnFocus says", async () => {
      const elsewhere = document.createElement("p");
      elsewhere.tabIndex = -1;
      document.body.append(elsewhere);
      const { wrapper, sheet, opener } = mountSheet(undefined, { returnFocus: elsewhere });
      opener.focus();
      sheet.open();
      await nextTick();
      sheet.close();
      await nextTick();
      expect(document.activeElement).toBe(opener);
      wrapper.unmount();
      elsewhere.remove();
    });
  });

  describe("describedBy (ux a11y A1: a reason-first danger sheet is described by its consequence)", () => {
    it("sets the dialog's aria-describedby to the given id", () => {
      const { wrapper } = mountSheet("textarea", { describedBy: "revoke-consequence" });
      expect(wrapper.get("dialog").attributes("aria-describedby")).toBe("revoke-consequence");
      wrapper.unmount();
    });

    it("leaves aria-describedby off when it isn't given", () => {
      const { wrapper } = mountSheet();
      expect(wrapper.get("dialog").attributes("aria-describedby")).toBeUndefined();
      wrapper.unmount();
    });
  });
});
