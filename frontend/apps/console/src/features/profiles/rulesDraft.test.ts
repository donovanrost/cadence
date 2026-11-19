import { describe, expect, it } from "vite-plus/test";
import { draftProblems, newRule, toDocument } from "./rulesDraft.ts";

describe("profile rule drafts", () => {
  it("creates non-clashing rules and writes the stored document shape", () => {
    const a = newRule([]);
    const b = newRule([a]);
    expect([a.id, b.id]).toEqual(["rule-1", "rule-2"]);
    expect(toDocument([{ ...a, stationIds: ["svb"] }])[0]).toEqual({
      id: "rule-1",
      label: "Rule 1",
      name_template: "{station} · {spacecraft}",
      enabled: true,
      stations: [{ ground_station_id: "svb", transport_id: null }],
      legs: [{ direction: "downlink", role: "primary" }],
    });
  });

  it("flags rules without stations and unknown name tokens", () => {
    const rule = { ...newRule([]), nameTemplate: "{station} {plane}" };
    expect(draftProblems([rule])).toEqual([
      "Rule 1: pick at least one station.",
      "Rule 1: unknown token {plane}.",
    ]);
  });
});
