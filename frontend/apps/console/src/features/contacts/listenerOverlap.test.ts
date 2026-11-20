import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import ListenerOverlapNote from "./ListenerOverlapNote.vue";
import {
  listenerOverlapReader,
  overlapDuration,
  overlapTechnical,
  overlapWords,
  type ListenerOverlap,
} from "./listenerOverlap.ts";

/** U58 (b), #361 (ca-engineer's #640 shape): the overlap's words, every form. */
const raw = (over: Record<string, unknown> = {}, withOver: Record<string, unknown> = {}) => ({
  with: {
    spacecraft: { id: "sc-6", name: "EARENDIL-006" },
    station: { code: "SNTG", name: "Santiago" },
    starts_at: "2026-11-21T00:05:00Z",
    state: "booked",
    ...withOver,
  },
  seconds: 26,
  loses: "this",
  direction: "downlink",
  listener: { host: "0.0.0.0", port: 52001 },
  count: 1,
  ...over,
});
const read = (value: unknown): ListenerOverlap => {
  const r = decode(listenerOverlapReader, value);
  if (!r.ok) throw new Error(r.error.message);
  return r.value;
};
const said = (over?: Record<string, unknown>, withOver?: Record<string, unknown>) =>
  overlapWords(read(raw(over, withOver)));

describe("listener overlap words (U58 (b))", () => {
  it("tags the pass that may lose its start, with the sentence", () => {
    expect(said()).toEqual({
      tag: true,
      text: "Overlaps EARENDIL-006's SNTG 00:05Z pass by 26 s. Santiago's listener takes one connection at a time, so this pass may lose up to 26 s of its start.",
    });
  });

  it("gives the earlier pass a note, no tag", () => {
    expect(said({ loses: "other" }, { spacecraft: { id: "sc-1", name: "EARENDIL-001" } })).toEqual({
      tag: false,
      text: "EARENDIL-001's SNTG 00:05Z pass overlaps this one by 26 s and may lose up to 26 s of its start.",
    });
  });

  it("either: the tag and 'whichever connects second'", () => {
    expect(said({ loses: "either" })?.text).toBe(
      "Overlaps EARENDIL-006's SNTG 00:05Z pass by 26 s. Santiago's listener takes one connection at a time, and both claim it at once, so whichever connects second may lose up to 26 s of its start.",
    );
    expect(said({ loses: "either" })?.tag).toBe(true);
  });

  it("several: names the worst and counts the rest", () => {
    expect(said({ seconds: 40, count: 3 })?.text).toBe(
      "Overlaps EARENDIL-006's SNTG 00:05Z pass by 40 s and 2 other passes. Santiago's listener takes one connection at a time, so this pass may lose up to 40 s of its start.",
    );
    expect(said({ seconds: 40, count: 3, loses: "other" })?.text).toBe(
      "EARENDIL-006's SNTG 00:05Z pass and 2 other passes overlap this one; the longest overlap is 40 s.",
    );
    expect(said({ count: 2 })?.text).toContain("by 26 s and 1 other pass.");
  });

  it("nameless forms: an unknown spacecraft, the station's code, then 'The station's listener'", () => {
    expect(said({}, { spacecraft: { id: "sc-6", name: null } })?.text).toContain(
      "Overlaps an unknown spacecraft's SNTG 00:05Z pass by 26 s.",
    );
    expect(said({ loses: "other" }, { spacecraft: null })?.text).toBe(
      "An unknown spacecraft's SNTG 00:05Z pass overlaps this one by 26 s and may lose up to 26 s of its start.",
    );
    expect(said({}, { station: { code: "SNTG", name: null } })?.text).toContain(
      "SNTG's listener takes one connection at a time",
    );
    expect(said({}, { station: null })?.text).toBe(
      "Overlaps EARENDIL-006's 00:05Z pass by 26 s. The station's listener takes one connection at a time, so this pass may lose up to 26 s of its start.",
    );
  });

  it("durations past a minute, as §4", () => {
    expect(overlapDuration(100)).toBe("1 m 40 s");
    expect(overlapDuration(120)).toBe("2 m");
    expect(overlapDuration(3900)).toBe("1 h 5 m");
    expect(said({ seconds: 100 })?.text).toContain("may lose up to 1 m 40 s of its start");
  });

  it("open-ended (seconds null, #640): the sentence drops the number until ux words it", () => {
    expect(said({ seconds: null })?.text).toBe(
      "Overlaps EARENDIL-006's SNTG 00:05Z pass. Santiago's listener takes one connection at a time, so this pass may lose its start.",
    );
    expect(said({ seconds: null, loses: "either" })?.text).toBe(
      "Overlaps EARENDIL-006's SNTG 00:05Z pass. Santiago's listener takes one connection at a time, and both claim it at once, so whichever connects second may lose its start.",
    );
    expect(said({ seconds: null, loses: "other" })?.text).toBe(
      "EARENDIL-006's SNTG 00:05Z pass overlaps this one and may lose its start.",
    );
    expect(said({ seconds: null, loses: "other", count: 3 })?.text).toBe(
      "EARENDIL-006's SNTG 00:05Z pass and 2 other passes overlap this one.",
    );
  });

  it("a loses it doesn't know says nothing, never a guess", () => {
    expect(said({ loses: "both" })).toBeNull();
    expect(overlapWords(null)).toBeNull();
    expect(overlapWords(undefined)).toBeNull();
  });

  it("keeps the listener for Technical details, never the sentence", () => {
    expect(said()?.text).not.toContain("52001");
    expect(overlapTechnical(read(raw({ count: 3 })))).toBe(
      "listener 0.0.0.0:52001 · downlink · 26 s · 3 passes",
    );
  });

  it("renders the tag with its sentence, or the muted note", () => {
    const tagged = mount(ListenerOverlapNote, { props: { overlap: read(raw()) } });
    expect(tagged.text()).toContain("Listener overlap");
    expect(tagged.text()).toContain("so this pass may lose up to 26 s of its start.");
    const note = mount(ListenerOverlapNote, { props: { overlap: read(raw({ loses: "other" })) } });
    expect(note.text()).not.toContain("Listener overlap");
    expect(note.get("p").classes()).toContain("text-text-3");
    expect(mount(ListenerOverlapNote, { props: { overlap: null } }).html()).not.toContain("<p");
  });
});
