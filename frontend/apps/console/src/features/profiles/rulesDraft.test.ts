import { describe, expect, it } from "vite-plus/test";
import {
  draftProblems,
  newRule,
  rulePathWords,
  ruleRefusal,
  toDocument,
  unknownTokenError,
} from "./rulesDraft.ts";

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

  it("names every unknown token on the Route name field (#307: never 'Unknown token .')", () => {
    expect(unknownTokenError("{station} · {spacecraft}")).toBeNull();
    expect(unknownTokenError("{station} {plane}")).toBe("Unknown token {plane}.");
    expect(unknownTokenError("{plane} {orbit}")).toBe("Unknown tokens {plane} and {orbit}.");
    expect(unknownTokenError("{a} {b} {c}")).toBe("Unknown tokens {a}, {b} and {c}.");
    // A token typed twice is named once (mms-engineer, #323).
    expect(unknownTokenError("{plane}-{plane}")).toBe("Unknown token {plane}.");
    const rule = { ...newRule([]), stationIds: ["svb"], nameTemplate: "{plane} {orbit}" };
    expect(draftProblems([rule])).toEqual(["Rule 1: unknown tokens {plane} and {orbit}."]);
  });

  it("reads a server error path as the rule's label and field, never the path (#307, P2)", () => {
    const drafts = [
      { ...newRule([]), label: "Uplink pair" },
      { ...newRule([]), label: "  " },
    ];
    expect(rulePathWords("routing_rules.0.stations", drafts)).toBe("Uplink pair · Stations");
    expect(rulePathWords("routing_rules.0.stations.1.transport_id", drafts)).toBe(
      "Uplink pair · Stations",
    );
    expect(rulePathWords("routing_rules.1.name_template", drafts)).toBe("Rule 2 · Route name");
    expect(rulePathWords("routing_rules.4", drafts)).toBe("Rule 5");
    // Legs read as RuleLegs labels them; enabled is a button, so only the rule is named (#323).
    expect(rulePathWords("routing_rules.0.legs", drafts)).toBe("Uplink pair · Legs");
    expect(rulePathWords("routing_rules.0.legs.1.role", drafts)).toBe("Uplink pair · Leg 2 role");
    expect(rulePathWords("routing_rules.0.legs.0.direction", drafts)).toBe(
      "Uplink pair · Leg 1 direction",
    );
    expect(rulePathWords("routing_rules.0.legs.2", drafts)).toBe("Uplink pair · Leg 3");
    expect(rulePathWords("routing_rules.0.enabled", drafts)).toBe("Uplink pair");
    expect(rulePathWords("routing_rules.0.mystery", drafts)).toBe("Uplink pair");
    expect(rulePathWords("routing_rules", drafts)).toBe("Routing rules");
    expect(rulePathWords("something.else", drafts)).toBe("Routing rules");
  });

  it("opens a field refusal with the act: 'Not staged:' on Stage, 'Not checked:' on Check (#323)", () => {
    const drafts = [{ ...newRule([]), label: "Uplink pair" }];
    const errors = [
      { path: "routing_rules.0.stations", message: "pick a station this mission has" },
      { path: "routing_rules.0.legs.1.role", message: "is invalid" },
    ];
    expect(ruleRefusal(errors, drafts, "staged")).toBe(
      "Not staged: Uplink pair · Stations: pick a station this mission has · Uplink pair · Leg 2 role: is invalid",
    );
    expect(ruleRefusal(errors.slice(0, 1), drafts, "checked")).toBe(
      "Not checked: Uplink pair · Stations: pick a station this mission has",
    );
  });
});
