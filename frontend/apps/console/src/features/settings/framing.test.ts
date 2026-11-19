import { describe, expect, it } from "vite-plus/test";
import { profileFramingOff, type Settings } from "./index.ts";

const settings = (value: unknown): Settings => ({
  permissions: [],
  sections: [
    {
      key: "cadence.configuration",
      title: "Configuration",
      purpose: null,
      locked: undefined,
      version: null,
      fields: [
        {
          path: "profile_framing_generations",
          label: "Profile framing changes reach the runtime",
          type: "boolean",
          value,
          source: "mission",
          inherited_value: true,
        } as Settings["sections"][number]["fields"][number],
      ],
    },
  ],
});

describe("profile framing off (#45)", () => {
  it("is off only when the mission's value is explicitly false", () => {
    expect(profileFramingOff(settings(false))).toBe(true);
    expect(profileFramingOff(settings(true))).toBe(false);
    expect(profileFramingOff({ permissions: [], sections: [] })).toBe(false);
  });
});
