import { flushPromises, mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import { shortSelectionLabel } from "../model/time-range.ts";
import { refreshWords } from "./refresh-words.ts";
import ViewerActions from "./ViewerActions.vue";
import ViewerControls from "./ViewerControls.vue";

/** ux Dashboards.md §Phone (c2a94ec14): two fixed rows; refresh moves into ⋯. */
describe("viewer header on a phone", () => {
  it("shortens the range button", () => {
    expect(shortSelectionLabel({ kind: "sliding", seconds: 3_600 })).toBe("Last 1h");
    expect(shortSelectionLabel({ kind: "sliding", seconds: 900 })).toBe("Last 15m");
    expect(shortSelectionLabel({ kind: "default" })).toBe("Live");
    const day = {
      kind: "absolute" as const,
      from: "2026-11-14T02:00:00Z",
      to: "2026-11-14T04:00:00Z",
    };
    expect(shortSelectionLabel(day)).toBe("11-14 02:00–04:00Z");
    const night = { ...day, from: "2026-11-14T22:00:00Z", to: "2026-11-15T02:00:00Z" };
    expect(shortSelectionLabel(night)).toBe("11-14 22:00–11-15 02:00Z");
  });
  it("says the refresh interval in words", () => {
    expect(refreshWords("30s")).toBe("every 30 s");
    expect(refreshWords("1m")).toBe("every 1 min");
    expect(refreshWords("off")).toBe("off");
  });

  const props = {
    scopeOptions: [{ id: "sc1", name: "EARENDIL-312" }],
    spacecraft: "",
    selection: { kind: "sliding" as const, seconds: 3_600 },
    refresh: "30s" as const,
  };
  it("row 2 is scope and the short range, with no refresh select", () => {
    const w = mount(ViewerControls, { props: { ...props, phone: true } });
    expect(w.text()).toContain("Last 1h");
    expect(w.findAll("select")).toHaveLength(1);
    expect(w.get("label").text()).toBe("Spacecraft");
  });
  it("row 1's ⋯ carries Refresh, whose sheet applies a new interval", async () => {
    const w = mount(ViewerActions, {
      props: { ...props, canEdit: false, phone: true },
      attachTo: document.body,
    });
    // Only ⋯ in row 1: no scope, range or refresh controls here.
    expect(w.findAll("select")).toHaveLength(0);
    await w.get('button[aria-haspopup="menu"]').trigger("click");
    const item = w.findAll('[role="menuitem"]').find((b) => b.text().startsWith("Refresh"));
    expect(item?.text()).toBe("Refresh: every 30 s…");
    await item?.trigger("click");
    await flushPromises();
    const dialog = document.querySelector("dialog");
    expect(dialog?.open).toBe(true);
    const off = [
      ...document.querySelectorAll<HTMLInputElement>('input[name="dashboard-refresh"]'),
    ].find((i) => i.value === "off");
    off?.click();
    [...document.querySelectorAll("dialog footer button")]
      .find((b) => b.textContent?.trim() === "Apply")
      ?.dispatchEvent(new MouseEvent("click", { bubbles: true }));
    expect(w.emitted("refresh")?.[0]).toEqual(["off"]);
    w.unmount();
  });
});
