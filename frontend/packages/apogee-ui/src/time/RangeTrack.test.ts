import { mount } from "@vue/test-utils";
import { defineComponent, h, nextTick, ref } from "vue";
import { describe, expect, it, vi } from "vite-plus/test";
import ApSheet from "../ApSheet.vue";
import ApTimeRange from "../ApTimeRange.vue";

const H = 3_600_000;
const SPAN = { from: Date.UTC(2026, 10, 14, 0, 0), to: Date.UTC(2026, 10, 15, 0, 0) };
// jsdom has no layout or pointer capture: a 1000px track (24h → 36 s per px).
Element.prototype.setPointerCapture = () => undefined;
const x = (t: number) => ((t - SPAN.from) / (SPAN.to - SPAN.from)) * 1000;

function picker() {
  const w = mount(ApTimeRange, {
    props: {
      label: "Window",
      presets: [],
      span: SPAN,
      modelValue: { from: SPAN.from + 6 * H, to: SPAN.from + 8 * H },
    },
  });
  const track = w.get('[role="group"]');
  vi.spyOn(track.element, "getBoundingClientRect").mockReturnValue(
    DOMRect.fromRect({ x: 0, y: 0, width: 1000, height: 36 }),
  );
  const fields = () => w.findAll("input").map((i) => i.element.value);
  const at = async (part: string | null, from: number, to: number) => {
    const target = part ? w.get(`[data-part="${part}"]`) : track;
    await target.trigger("pointerdown", { button: 0, clientX: x(from), pointerId: 1 });
    await track.trigger("pointermove", { clientX: x(to), pointerId: 1 });
  };
  return { w, track, fields, at };
}

describe("dragging the range track (ux U62; the collapse bug)", () => {
  it("moves only the end that's grabbed, with From/To following live", async () => {
    const { w, track, fields, at } = picker();
    await at("end", SPAN.from + 8 * H, SPAN.from + 10 * H);
    expect(fields()).toEqual(["2026-11-14 06:00:00Z", "2026-11-14 10:00:00Z"]);
    expect(w.emitted("update:modelValue")).toBeUndefined();
    await track.trigger("pointerup", { pointerId: 1 });
    expect(w.emitted("update:modelValue")?.at(-1)).toEqual([
      { from: SPAN.from + 6 * H, to: SPAN.from + 10 * H },
    ]);
  });
  it("moves the whole window when the band's body is dragged", async () => {
    const { w, track, at } = picker();
    await at("band", SPAN.from + 7 * H, SPAN.from + 9 * H);
    await track.trigger("pointerup", { pointerId: 1 });
    expect(w.emitted("update:modelValue")?.at(-1)).toEqual([
      { from: SPAN.from + 8 * H, to: SPAN.from + 10 * H },
    ]);
  });
  it("draws a new range on empty track", async () => {
    const { w, track, at } = picker();
    await at(null, SPAN.from + 12 * H, SPAN.from + 15 * H);
    await track.trigger("pointerup", { pointerId: 1 });
    expect(w.emitted("update:modelValue")?.at(-1)).toEqual([
      { from: SPAN.from + 12 * H, to: SPAN.from + 15 * H },
    ]);
  });
  it("restores everything on Esc", async () => {
    const { w, track, fields, at } = picker();
    await at("start", SPAN.from + 6 * H, SPAN.from + 2 * H);
    expect(fields()[0]).toBe("2026-11-14 02:00:00Z");
    window.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }));
    await nextTick();
    await track.trigger("pointerup", { pointerId: 1 });
    expect(fields()).toEqual(["2026-11-14 06:00:00Z", "2026-11-14 08:00:00Z"]);
    expect(w.emitted("update:modelValue")).toBeUndefined();
  });
  it("ignores a click that moves under 4px", async () => {
    const { w, track } = picker();
    await track.trigger("pointerdown", { button: 0, clientX: 500, pointerId: 1 });
    await track.trigger("pointermove", { clientX: 502, pointerId: 1 });
    await track.trigger("pointerup", { pointerId: 1 });
    expect(w.emitted("update:modelValue")).toBeUndefined();
  });
  it("nudges a handle from the keyboard and says the new range", async () => {
    const { w } = picker();
    await w.get('[data-part="end"]').trigger("keydown", { key: "ArrowRight" });
    expect(w.emitted("update:modelValue")?.at(-1)).toEqual([
      { from: SPAN.from + 6 * H, to: SPAN.from + 8 * H + 15 * 60_000 },
    ]);
    expect(w.get('[aria-live="polite"]').text()).toBe("Range 11-14 06:00Z–08:15Z");
  });
  it("Esc mid-drag cancels only the drag inside a sheet; Esc after closes the sheet (lead)", async () => {
    // jsdom fires no native dialog 'cancel', so the side sheet's own Escape (keydown) stands in:
    // the drag's capture-phase handler must stop it, and must let a drag-free Esc through.
    const range = ref({ from: SPAN.from + 6 * H, to: SPAN.from + 8 * H });
    const Host = defineComponent(
      () => () =>
        h(ApSheet, { title: "Pick a window", placement: "side" }, () =>
          h(ApTimeRange, {
            label: "Window",
            presets: [],
            span: SPAN,
            modelValue: range.value,
            "onUpdate:modelValue": (r: { from: number; to: number }) => (range.value = r),
          }),
        ),
    );
    const w = mount(Host, { attachTo: document.body });
    const dialog = w.get("dialog").element;
    if (!(dialog instanceof HTMLDialogElement)) throw new Error("ApSheet renders a <dialog>");
    dialog.show(); // what ApSheet.open() does for a side sheet
    await nextTick();
    expect(dialog.open).toBe(true);
    const track = w.get('[role="group"]');
    vi.spyOn(track.element, "getBoundingClientRect").mockReturnValue(
      DOMRect.fromRect({ x: 0, y: 0, width: 1000, height: 36 }),
    );
    await w.get('[data-part="start"]').trigger("pointerdown", {
      button: 0,
      clientX: x(SPAN.from + 6 * H),
      pointerId: 1,
    });
    await track.trigger("pointermove", { clientX: x(SPAN.from + 2 * H), pointerId: 1 });
    track.element.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
    await nextTick();
    expect(dialog.open).toBe(true);
    expect(w.findAll("input")[0]?.element.value).toBe("2026-11-14 06:00:00Z");
    track.element.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
    await nextTick();
    expect(dialog.open).toBe(false);
    expect(range.value).toEqual({ from: SPAN.from + 6 * H, to: SPAN.from + 8 * H });
    w.unmount();
  });
});
