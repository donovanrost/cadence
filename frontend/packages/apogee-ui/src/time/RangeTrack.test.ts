import { mount } from "@vue/test-utils";
import { nextTick } from "vue";
import { describe, expect, it, vi } from "vite-plus/test";
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
});
