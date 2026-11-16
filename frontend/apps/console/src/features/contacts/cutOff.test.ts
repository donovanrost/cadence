import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import CutOffNote from "./CutOffNote.vue";
import { cutOffWords } from "./cutOff.ts";

/** ux U67 · bytes cut off at the end of a pass (api: GET /passes/:id incomplete_at_end). */
const c = (frame_bytes: number, packet_bytes: number) => ({ frame_bytes, packet_bytes });

describe("cut off at the end of a pass", () => {
  it("words the non-zero side, or both", () => {
    expect(cutOffWords(c(6, 0))).toBe(
      "6 bytes at the end of the pass didn't form a complete frame, so they weren't stored.",
    );
    expect(cutOffWords(c(0, 12))).toBe(
      "12 bytes at the end of the pass didn't form a complete packet, so they weren't stored.",
    );
    expect(cutOffWords(c(6, 12))).toBe(
      "6 bytes at the end of the pass didn't form a complete frame, and 12 didn't form a complete packet, so they weren't stored.",
    );
    expect(cutOffWords(c(1, 0))).toBe(
      "1 byte at the end of the pass didn't form a complete frame, so it wasn't stored.",
    );
  });

  it("says nothing when nothing was cut off, unknown, or an older read", () => {
    expect(cutOffWords(null)).toBeNull();
    expect(cutOffWords(undefined)).toBeNull();
    expect(cutOffWords(c(0, 0))).toBeNull();
    expect(mount(CutOffNote, { props: { cutOff: null } }).html()).not.toContain("<p");
  });

  it("is a quiet note: secondary text, no mark or status colour", () => {
    const p = mount(CutOffNote, { props: { cutOff: c(6, 0) } }).find("p");
    expect(p.classes()).toContain("text-text-3");
    expect(p.find(".ap-mark").exists()).toBe(false);
  });
});
