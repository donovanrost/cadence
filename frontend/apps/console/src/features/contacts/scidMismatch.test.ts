import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api/index.ts";
import { passReader } from "./api.ts";
import ScidMismatchNote from "./ScidMismatchNote.vue";
import { scidMismatchIds, scidMismatchLines } from "./scidMismatch.ts";

/** ux U81 §2 · frames refused for another SCID (api: GET /passes/:id scid_mismatch). */
const FBK = { ref: "fbk", id: "gs-fbk", code: "FBK", name: "Fairbanks" };
const SVA = { ref: "sva", id: "gs-sva", code: "SVA", name: null };
const path = (o: Record<string, unknown> = {}) => ({
  station: FBK,
  frames: 412,
  scids: [3],
  scid_count: 1,
  path_id: "path-1",
  provider_binding_id: "pb-1",
  ...o,
});

/** A pass row as api serves it, decoded as the screen reads it; returns its scid_mismatch. */
const mismatchOf = (paths: unknown[] | null) => {
  const r = decode(passReader, {
    id: "pass-7",
    kind: "contact",
    state: "confirmed",
    pass_phase: "completed",
    delivery_state: "delivered",
    spacecraft_id: "spacecraft-earendil-312",
    spacecraft: { id: "spacecraft-earendil-312", name: "EARENDIL-312", scid: 1 },
    station: FBK,
    antenna: null,
    starts_at: "2026-11-14T03:10:00Z",
    ends_at: "2026-11-14T03:20:00Z",
    uplink_capable: true,
    source: { provider: "p-1", provider_name: "Northlight", synthetic: false },
    max_elevation_deg: null,
    elevation_source: null,
    predicted_pass_id: null,
    plan: null,
    ended_by: null,
    replaced_by: null,
    booking_evidence: null,
    attested_by: null,
    uplink_confirmed: null,
    attention: null,
    uplink_readiness: null,
    provider_revision: null,
    scid_mismatch: paths ? { expected_scid: 1, paths } : null,
  });
  if (!r.ok) throw new Error(r.error.message);
  return r.value.scid_mismatch;
};
const lines = (paths: unknown[] | null, sc: string | null = "EARENDIL-312") =>
  scidMismatchLines(mismatchOf(paths), sc);
const TAIL = "Cadence kept them as raw evidence and made no telemetry from them.";

describe("frames with another SCID (U81 §2)", () => {
  it("words one path with no station clause", () => {
    expect(lines([path()])).toEqual([
      `412 frames with SCID 3 arrived during this pass, which is EARENDIL-312's (SCID 1). ${TAIL}`,
    ]);
    expect(lines([path({ frames: 1 })])).toEqual([
      "1 frame with SCID 3 arrived during this pass, which is EARENDIL-312's (SCID 1). Cadence kept it as raw evidence and made no telemetry from it.",
    ]);
    expect(lines([path()], null)[0]).toContain("during this pass, which expected SCID 1.");
  });

  it("lists up to three SCIDs, then counts them", () => {
    const w = (scids: number[], scid_count = scids.length) =>
      lines([path({ scids, scid_count })])[0];
    expect(w([3, 7])).toContain("with SCIDs 3 and 7 arrived");
    expect(w([3, 7, 9])).toContain("with SCIDs 3, 7 and 9 arrived");
    expect(w([2, 3, 7, 9])).toContain("with 4 different SCIDs arrived");
    expect(w([1, 2, 3, 4, 5, 6, 7, 8], 12)).toContain("with 12 different SCIDs arrived");
  });

  it("merges paths through the same station: frames summed, SCIDs unioned when complete", () => {
    expect(
      lines([path(), path({ path_id: "path-2", frames: 8, scids: [3, 7], scid_count: 2 })]),
    ).toEqual([
      `420 frames with SCIDs 3 and 7 arrived during this pass, which is EARENDIL-312's (SCID 1). ${TAIL}`,
    ]);
    const capped = [1, 2, 3, 4, 5, 6, 7, 8];
    expect(
      lines([
        path({ scids: capped, scid_count: 10 }),
        path({ path_id: "path-2", scids: [9], scid_count: 1 }),
      ])[0],
    ).toContain("824 frames with at least 10 different SCIDs arrived during");
  });

  it("names the station (name, else code) only when two or more remain", () => {
    expect(lines([path(), path({ path_id: "path-2", station: SVA, frames: 5 })])).toEqual([
      `412 frames with SCID 3 arrived through Fairbanks during this pass, which is EARENDIL-312's (SCID 1). ${TAIL}`,
      `5 frames with SCID 3 arrived through SVA during this pass, which is EARENDIL-312's (SCID 1). ${TAIL}`,
    ]);
    const none = lines([path(), path({ path_id: "path-2", station: null, frames: 5 })]);
    expect(none[1]).toContain("5 frames with SCID 3 arrived during this pass");
    expect(none.join(" ")).not.toContain("path-");
  });

  it("puts ids and the SCID list in Technical details, never in the words", () => {
    const m = mismatchOf([path({ scids: [1, 2, 3, 4, 5, 6, 7, 8], scid_count: 12 })]);
    expect(scidMismatchIds(m)).toEqual([
      "Path path-1 · provider binding pb-1 · SCIDs 1, 2, 3, 4, 5, 6, 7, 8 (8 of 12)",
    ]);
    expect(scidMismatchIds(mismatchOf([path({ provider_binding_id: null })]))).toEqual([
      "Path path-1 · SCIDs 3",
    ]);
  });

  it("says nothing with no mismatch or an older read", () => {
    expect(lines(null)).toEqual([]);
    expect(scidMismatchLines(undefined, "EARENDIL-312")).toEqual([]);
    const w = mount(ScidMismatchNote, { props: { mismatch: null, spacecraft: null } });
    expect(w.html()).not.toContain("<p");
  });

  it("is a caution line at full contrast, unlike U67's quiet note", () => {
    const w = mount(ScidMismatchNote, {
      props: { mismatch: mismatchOf([path()]), spacecraft: "EARENDIL-312" },
    });
    const p = w.find("p");
    expect(p.classes()).toContain("text-readout");
    expect(p.find(".ap-mark--caution").exists()).toBe(true);
    expect(w.find("summary").text()).toBe("Technical details");
  });
});
