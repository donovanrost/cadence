import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import EphemerisCounts from "./EphemerisCounts.vue";
import { ephemerisReader, ephemerisSummary, type Ephemeris } from "./ephemeris.ts";

/** #975, setup.md "Mission providers": a provider row's `ephemeris`. */
const zero = {
  uploaded: 0,
  failed: 0,
  not_ready: 0,
  pending: 0,
  lookup: 0,
  norad_id_missing: 0,
};
const ephemeris = (over: Record<string, unknown>): Ephemeris => {
  const r = decode(ephemerisReader, { orbit_source: "accepts_ephemeris_upload", ...zero, ...over });
  if (!r.ok) throw new Error(JSON.stringify(r.error));
  return r.value;
};
const lines = (e: Ephemeris) =>
  ephemerisSummary(e).lines.map((l) => [l.key, l.text, l.caution, l.note]);

describe("ephemeris decoding", () => {
  it("tolerates an unknown source and a row from before not_ready (#981)", () => {
    expect(ephemeris({ orbit_source: "relay" }).orbit_source).toBe("unrecognized");
    expect(ephemeris({ orbit_source: null }).orbit_source).toBeNull();
    const { not_ready: _, ...older } = zero;
    const r = decode(ephemerisReader, { orbit_source: null, ...older });
    expect(r.ok && r.value.not_ready).toBeUndefined();
    expect(decode(ephemerisReader, { orbit_source: null, ...zero, failed: null }).ok).toBe(false);
  });
});

describe("ephemeris words (#975: every non-zero bucket)", () => {
  it("an upload provider: its upload buckets, failed and not ready as cautions", () => {
    const e = ephemeris({ uploaded: 1200, failed: 2, not_ready: 3, pending: 1 });
    const s = ephemerisSummary(e);
    expect(s.lead).toBe("Cadence uploads orbits");
    expect(s.total).toBe("1,206 spacecraft with an orbit");
    expect(lines(e)).toEqual([
      ["uploaded", "1,200 uploaded", false, null],
      ["failed", "2 upload failed, retrying", true, null],
      ["not_ready", "3 not ready, no route to this provider is ready, nothing sent", true, null],
      ["pending", "1 waiting to upload", false, null],
    ]);
  });

  it("a lookup provider: looked up, and without a NORAD id as a caution", () => {
    const e = ephemeris({ orbit_source: "looks_up_by_norad_id", lookup: 7, norad_id_missing: 1 });
    expect(ephemerisSummary(e).lead).toBe("Looks orbits up by NORAD id");
    expect(lines(e)).toEqual([
      ["lookup", "7 looked up by NORAD id", false, null],
      ["norad_id_missing", "1 without a NORAD id, the provider can't find them", true, null],
    ]);
  });

  it("no declared source: says so, and marks its lookup buckets as assumed", () => {
    const e = ephemeris({ orbit_source: null, lookup: 4, norad_id_missing: 2 });
    expect(ephemerisSummary(e).lead).toBe("Orbit source not declared");
    expect(lines(e).map((l) => l[3])).toEqual(["assumed", "assumed"]);
  });

  it("a mixed row: its own kind first, the other kind as an older pinned version's", () => {
    const e = ephemeris({ orbit_source: "looks_up_by_norad_id", uploaded: 2, lookup: 5 });
    expect(lines(e)).toEqual([
      ["lookup", "5 looked up by NORAD id", false, null],
      ["uploaded", "2 uploaded", false, "older pinned version"],
    ]);
    const undeclared = ephemeris({ orbit_source: null, failed: 1, lookup: 3 });
    expect(lines(undeclared).map((l) => [l[0], l[3]])).toEqual([
      ["lookup", "assumed"],
      ["failed", "older pinned version"],
    ]);
  });

  it("an unknown source: says so and keeps every non-zero bucket, unqualified", () => {
    const e = ephemeris({ orbit_source: "relay", uploaded: 1, norad_id_missing: 1 });
    expect(ephemerisSummary(e).lead).toBe("Orbit source not recognized");
    expect(lines(e).map((l) => [l[0], l[3]])).toEqual([
      ["uploaded", null],
      ["norad_id_missing", null],
    ]);
  });

  it("no spacecraft with an orbit: an honest line, never a row of zeros", () => {
    const s = ephemerisSummary(ephemeris({}));
    expect(s.total).toBe("No bound spacecraft has an orbit yet");
    expect(s.lines).toEqual([]);
    expect(ephemerisSummary(ephemeris({ not_ready: undefined, pending: 1 })).total).toBe(
      "1 spacecraft with an orbit",
    );
  });
});

describe("EphemerisCounts", () => {
  it("shows a caution as mark, color and word, and no zero counts", () => {
    const w = mount(EphemerisCounts, {
      props: { ephemeris: ephemeris({ uploaded: 3, failed: 1 }) },
    });
    expect(w.findAll("[data-bucket]").map((li) => li.attributes("data-bucket"))).toEqual([
      "uploaded",
      "failed",
    ]);
    const failed = w.find('[data-bucket="failed"]');
    expect(failed.classes()).toContain("text-caution-text");
    expect(failed.find(".ap-mark--caution").exists()).toBe(true);
    expect(failed.text()).toBe("1 upload failed, retrying");
    expect(w.find('[data-bucket="uploaded"] .ap-mark--caution').exists()).toBe(false);
    w.unmount();
    const empty = mount(EphemerisCounts, { props: { ephemeris: ephemeris({}) } });
    expect(empty.text()).toBe("Cadence uploads orbitsNo bound spacecraft has an orbit yet");
    expect(empty.find("ul").exists()).toBe(false);
    empty.unmount();
  });
});
