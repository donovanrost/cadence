import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { policiesReader, policyText } from "./policies.ts";

describe("policyText (U4)", () => {
  it("writes each live policy as a title and one sentence; unknown keys say so", () => {
    const r = decode(policiesReader, {
      policies: [
        {
          key: "command_classification",
          parameters: { classifications: ["hazardous", "critical"] },
        },
        {
          key: "policy_hint",
          parameters: { hints: ["confirmation_required", "approval_required"] },
        },
        { key: "fleet_reach", parameters: { threshold: 10 } },
        { key: "no_self_approval", parameters: {} },
        { key: "night_shift_lock", parameters: {} },
      ],
    });
    if (!r.ok) throw r.error;
    expect(r.value.policies.map((p) => policyText(p).sentence)).toEqual([
      "Hazardous and critical commands need a second GO from another person who can approve.",
      "Commands the catalog marks as needing confirmation or approval also need a second GO.",
      "Any request to 10 or more spacecraft needs a second GO.",
      "Nobody can give the second GO on their own request.",
      "The server applies this policy; the console doesn't describe it yet.",
    ]);
    expect(
      policyText(r.value.policies[4] ?? { key: { unrecognized: "x" }, parameters: {} }).title,
    ).toBe("Night shift lock");
  });
});
