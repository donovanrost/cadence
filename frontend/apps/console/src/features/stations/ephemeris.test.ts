import { mount, RouterLinkStub } from "@vue/test-utils";
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
  it("tolerates an unknown source; every bucket is a required integer", () => {
    expect(ephemeris({ orbit_source: "relay" }).orbit_source).toBe("unrecognized");
    expect(ephemeris({ orbit_source: null }).orbit_source).toBeNull();
    const { not_ready: _, ...older } = zero;
    expect(decode(ephemerisReader, { orbit_source: null, ...older }).ok).toBe(false);
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
      ["not_ready", "3 not ready, no route to this provider is ready", true, null],
      ["pending", "1 waiting for a check", false, null],
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

  it("not ready and pending are neither kind (#981): last, never older or assumed", () => {
    const e = ephemeris({
      orbit_source: "looks_up_by_norad_id",
      pending: 2,
      uploaded: 1,
      lookup: 3,
    });
    expect(lines(e)).toEqual([
      ["lookup", "3 looked up by NORAD id", false, null],
      ["uploaded", "1 uploaded", false, "older pinned version"],
      ["pending", "2 waiting for a check", false, null],
    ]);
    expect(lines(ephemeris({ orbit_source: null, pending: 1 }))).toEqual([
      ["pending", "1 waiting for a check", false, null],
    ]);
    const notReady = ["not_ready", "2 not ready, no route to this provider is ready", true, null];
    expect(lines(ephemeris({ orbit_source: "looks_up_by_norad_id", not_ready: 2 }))).toEqual([
      notReady,
    ]);
    expect(lines(ephemeris({ orbit_source: null, lookup: 1, not_ready: 2 }))).toEqual([
      ["lookup", "1 looked up by NORAD id", false, "assumed"],
      notReady,
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
    expect(ephemerisSummary(ephemeris({ pending: 1 })).total).toBe("1 spacecraft with an orbit");
  });
});

describe("EphemerisCounts", () => {
  it("shows a caution as mark, color and word, and no zero counts", () => {
    const w = mount(EphemerisCounts, {
      props: { ephemeris: ephemeris({ uploaded: 3, failed: 1 }), providerId: "prov_1" },
      global: { stubs: { RouterLink: RouterLinkStub } },
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
    const empty = mount(EphemerisCounts, {
      props: { ephemeris: ephemeris({}), providerId: "prov_1" },
      global: { stubs: { RouterLink: RouterLinkStub } },
    });
    expect(empty.text()).toBe("Cadence uploads orbitsNo bound spacecraft has an orbit yet");
    expect(empty.find("ul").exists()).toBe(false);
    empty.unmount();
  });
});

describe("EphemerisCounts links (#972 member list)", () => {
  it("links each non-zero failed, not ready and without-NORAD-id line by its cause, and nothing else", () => {
    const w = mount(EphemerisCounts, {
      props: {
        ephemeris: ephemeris({
          orbit_source: "accepts_ephemeris_upload",
          uploaded: 4,
          failed: 1,
          not_ready: 2,
          pending: 1,
          lookup: 3,
          norad_id_missing: 1,
        }),
        providerId: "prov_1",
        linked: true,
      },
      global: { stubs: { RouterLink: RouterLinkStub } },
    });
    const to = (cause: string) => ({
      name: "setup.stations.providers",
      params: { providerId: "prov_1" },
      query: { cause },
    });
    // The links, in the order shown (own kind first), and the lines that hold one.
    expect(w.findAllComponents(RouterLinkStub).map((l) => [l.props("to"), l.text()])).toEqual([
      [to("failed"), "1 upload failed, retrying"],
      [to("norad_id_missing"), "1 without a NORAD id, the provider can't find them"],
      [to("not_ready"), "2 not ready, no route to this provider is ready"],
    ]);
    const linked = w
      .findAll("li")
      .filter((li) => li.find("a").exists())
      .map((li) => li.attributes("data-bucket"));
    expect(linked).toEqual(["failed", "norad_id_missing", "not_ready"]);
    w.unmount();
  });
});
