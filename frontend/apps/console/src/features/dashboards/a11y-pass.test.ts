import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it } from "vite-plus/test";
import { nextTick } from "vue";
import EditSectionHead from "./editor/EditSectionHead.vue";
import { focusLost, inDialog, refocus } from "./focus-fallback.ts";
import PresentLine from "./playlists/PresentLine.vue";

/** ux's a11y checklist (docs/apogee/ux/a11y-checklist.md), run by dashboards before qa's §6 pass. */
afterEach(() => {
  document.body.innerHTML = "";
});

describe("focus fallback (A5)", () => {
  it("moves lost focus to the fallback, making a heading focusable without joining Tab order", () => {
    document.body.innerHTML = `<h1>Dashboards</h1><button id="gone">⋯</button>`;
    const gone = document.getElementById("gone");
    gone?.focus();
    gone?.remove();
    expect(focusLost()).toBe(true);
    const h1 = document.querySelector("h1");
    refocus(h1);
    expect(document.activeElement).toBe(h1);
    expect(h1?.getAttribute("tabindex")).toBe("-1");
  });
  it("leaves focus alone when the user is already somewhere", () => {
    document.body.innerHTML = `<h1>Dashboards</h1><input id="search" />`;
    const search = document.getElementById("search");
    search?.focus();
    refocus(document.querySelector("h1"));
    expect(document.activeElement).toBe(search);
  });
  it("tells a key from inside a sheet apart from one on the takeover (kiosk, present)", () => {
    document.body.innerHTML = `<dialog open><button id="in">Close</button></dialog><button id="out">x</button>`;
    const key = (id: string) => {
      const event = new KeyboardEvent("keydown", { key: "Escape" });
      Object.defineProperty(event, "target", { value: document.getElementById(id) });
      return event;
    };
    expect(inDialog(key("in"))).toBe(true);
    expect(inDialog(key("out"))).toBe(false);
  });
});

describe("in-place Remove section confirm (A1, A5)", () => {
  const section = { id: "s1", title: "Power", description: "", collapsed_by_default: false };
  it("opens on Cancel, never on Remove, and Cancel returns focus to the ⋯", async () => {
    const w = mount(EditSectionHead, {
      props: { section, count: 2, first: true, last: true },
      attachTo: document.body,
    });
    const trigger = w.get('button[aria-label="More section actions"]');
    await trigger.trigger("click");
    await w
      .findAll("button")
      .find((b) => b.text().startsWith("Remove section"))
      ?.trigger("click");
    await flushPromises();
    expect(document.activeElement?.textContent?.trim()).toBe("Cancel");
    await w
      .findAll("button")
      .find((b) => b.text() === "Cancel")
      ?.trigger("click");
    await flushPromises();
    expect(document.activeElement).toBe(trigger.element);
    w.unmount();
  });
});

describe("present line (B4)", () => {
  it("announces a step or a pause, not the countdown", async () => {
    document.body.innerHTML = `<div id="ap-takeover-header"></div>`;
    const props = { name: "Ops wall", position: 2, total: 5, remainingMs: 18_000, paused: false };
    const w = mount(PresentLine, {
      props: { ...props, skipped: 0 },
      attachTo: document.body,
      global: { stubs: { CockpitStatus: true } },
    });
    await nextTick();
    const live = () => document.querySelector('[aria-live="polite"]')?.textContent?.trim();
    expect(live()).toBe("2 of 5");
    await w.setProps({ remainingMs: 17_000 });
    expect(live()).toBe("2 of 5");
    await w.setProps({ paused: true });
    expect(live()).toBe("2 of 5, paused");
    w.unmount();
  });
});
