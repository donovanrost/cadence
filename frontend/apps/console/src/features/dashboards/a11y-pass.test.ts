import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it } from "vite-plus/test";
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
      props: { section, count: 2, first: true, last: true, position: 1 },
      attachTo: document.body,
    });
    const trigger = w.get('button[aria-label^="More actions for section"]');
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

describe("present line (B4; ux Dashboards.md, Present)", () => {
  function present() {
    document.body.innerHTML = `<div id="ap-takeover-header"></div>`;
    const props = {
      name: "Ops wall",
      current: "Power overview",
      position: 2,
      total: 5,
      remainingMs: 18_000,
      paused: false,
      failed: false,
      skipped: 0,
    };
    return mount(PresentLine, {
      props,
      attachTo: document.body,
      global: { stubs: { CockpitStatus: true } },
    });
  }
  const live = () => document.querySelector('[aria-live="polite"]')?.textContent?.trim();

  it("names the dashboard, then its position, on each step and pause; never the countdown", async () => {
    const w = present();
    await flushPromises();
    expect(live()).toBe("Power overview, 2 of 5");
    await w.setProps({ remainingMs: 17_000 });
    expect(live()).toBe("Power overview, 2 of 5");
    await w.setProps({ paused: true });
    expect(live()).toBe("Paused: Power overview, 2 of 5");
    await w.setProps({ paused: false });
    expect(live()).toBe("Playing: Power overview, 2 of 5");
    await w.setProps({ current: "Thermal", position: 3 });
    expect(live()).toBe("Thermal, 3 of 5");
    await w.setProps({ failed: true });
    expect(live()).toBe("Thermal couldn't load, 3 of 5");
    expect(document.querySelector("header span.font-mono")?.textContent).toContain(
      "Thermal · 3 of 5",
    );
    w.unmount();
  });
  it("takes focus on its own h1 when it opens (it sits outside <main>)", async () => {
    const w = present();
    await flushPromises();
    expect(document.activeElement?.tagName).toBe("H1");
    expect(document.activeElement?.textContent?.trim()).toBe("Playlist · Ops wall");
    w.unmount();
  });
});
