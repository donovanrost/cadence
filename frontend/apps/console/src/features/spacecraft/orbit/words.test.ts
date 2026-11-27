import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { coverageReader, elementSetReader, predictedPassReader } from "./api.ts";
import { coverageWire, elementSetWire, passWire } from "./fixtures.ts";
import { coverageLines, currentFacts, elevation, sourceLine, stationLine } from "./words.ts";

/** #895: the Orbit section's words, from the wire. */
const set = (over: Record<string, unknown> = {}) => {
  const r = decode(elementSetReader, elementSetWire(over));
  if (!r.ok) throw new Error(JSON.stringify(r.error));
  return r.value;
};
const pass = (over: Record<string, unknown> = {}) => {
  const r = decode(predictedPassReader, passWire(over));
  if (!r.ok) throw new Error(JSON.stringify(r.error));
  return r.value;
};
const coverage = (over: Record<string, unknown> = {}, u: Record<string, number> = {}) => {
  const r = decode(coverageReader, { coverage: coverageWire(over, u) });
  if (!r.ok) throw new Error(JSON.stringify(r.error));
  return r.value.coverage;
};
const now = new Date("2026-11-27T15:28:39Z");
const to = "2026-12-04T00:00:00.000Z";

describe("element set decoding", () => {
  it("reads format and source as closed vocabularies that tolerate a new value", () => {
    expect(set().format).toBe("tle");
    expect(set({ format: "omm", source: "api" })).toMatchObject({ format: "omm", source: "api" });
    expect(set({ format: "kvn", source: "feed" })).toMatchObject({
      format: "unrecognized",
      source: "unrecognized",
    });
  });

  it("requires the epoch, and a pass's name and epoch; a pass's SCID may be null", () => {
    expect(decode(elementSetReader, elementSetWire({ epoch: null })).ok).toBe(false);
    expect(decode(predictedPassReader, passWire({ spacecraft: { id: "s", scid: 1 } })).ok).toBe(
      false,
    );
    expect(
      decode(predictedPassReader, passWire({ element_set: { id: "e", epoch: null } })).ok,
    ).toBe(false);
    expect(pass({ spacecraft: { id: "s", name: "S", scid: null } }).spacecraft.scid).toBeNull();
  });
});

describe("currentFacts", () => {
  it("shows format, epoch with its age, source, object name and NORAD id", () => {
    expect(currentFacts(set(), now).map((f) => [f.label, f.value])).toEqual([
      ["Format", "TLE"],
      ["Epoch", "2026-11-26 12:00:00Z"],
      ["Age", "T+1d 03:28:39"],
      ["Source", "Manual · Mira K."],
      ["Object name", "EARENDIL-312"],
      ["NORAD id", "25544"],
    ]);
  });

  it("says what the set doesn't carry, and a source without a known person", () => {
    const facts = currentFacts(set({ object_name: null, norad_id: null, created_by: null }), now);
    expect(facts.find((f) => f.key === "object")?.value).toBe("Not in the element set");
    expect(facts.find((f) => f.key === "norad")?.value).toBe("Not in the element set");
    expect(sourceLine(set({ source: "api", created_by: null }))).toBe("API");
  });
});

describe("pass words", () => {
  it("names the station with its code, and a station that's gone as unknown", () => {
    expect(stationLine(pass())).toBe("Svalbard · SVA");
    expect(stationLine(pass({ station: { id: "g", display_name: null, code: null } }))).toBe(
      "Unknown station",
    );
    expect(elevation(38.24)).toBe("38.2°");
  });
});

describe("coverageLines (predicted-passes.md §Coverage)", () => {
  it("says nothing when the whole window is computed and nothing is unpredicted", () => {
    expect(coverageLines(coverage(), to)).toEqual([]);
  });

  it("shows the partial line when the horizon ends before the window does", () => {
    const lines = coverageLines(coverage({ horizon_end: "2026-12-01T00:00:00Z" }), to);
    expect(lines.map((l) => l.text)).toEqual([
      "Passes are predicted up to 12-01 00:00Z. Later passes aren't computed yet, so none are shown after it.",
    ]);
  });

  it("says a deep-space orbit isn't predicted yet, in plain words", () => {
    const lines = coverageLines(coverage({}, { spacecraft_deep_space: 1 }), to);
    expect(lines[0]?.text).toBe(
      "This spacecraft's orbit is deep space (a period of 225 minutes or more). Cadence doesn't predict passes for deep-space orbits yet.",
    );
  });

  it("says before the first run, stations without a location, and passes that couldn't be timed", () => {
    expect(coverageLines(coverage({ horizon_end: null }), to)[0]?.text).toBe(
      "Passes haven't been predicted for this mission yet.",
    );
    const lines = coverageLines(
      coverage({}, { stations_without_location: 2, passes_not_bracketed: 1 }),
      to,
    );
    expect(lines.map((l) => [l.tone, l.text])).toEqual([
      ["caution", "2 stations have no location, so their passes aren't predicted."],
      [
        "caution",
        "1 pass couldn't be timed, so it wasn't stored. The element set may be wrong; check its epoch.",
      ],
    ]);
    expect(coverageLines(coverage({}, { stations_without_location: 1 }), to)[0]?.text).toBe(
      "1 station has no location, so its passes aren't predicted.",
    );
  });
});
