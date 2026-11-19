import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { afterText, beforeText } from "./api.ts";
import { diffField } from "./preview.ts";
import { field } from "./shapes.ts";

/** api's U83 example row: a hidden reset of a shared listener. */
const reset = {
  path: "configuration.listener",
  label: "Listener",
  unit: null,
  before: "shared",
  after: null,
  before_label: "Shared, routed by SCID",
  after_label: "Own listener for each pass",
  note: "only a downlink transport that listens can share one",
};

describe("diff rows read the option's words (ux U83, api)", () => {
  it("shows the labels and the reason in brackets, on revisions and previews alike", () => {
    for (const reader of [field, diffField]) {
      const row = decode(reader, reset);
      if (!row.ok) throw row.error;
      expect(beforeText(row.value)).toBe("Shared, routed by SCID");
      expect(afterText(row.value)).toBe(
        "Own listener for each pass (only a downlink transport that listens can share one)",
      );
    }
  });

  it("shows the raw value when there are no labels, before and after api sends the keys", () => {
    const { before_label: _b, after_label: _a, note: _n, ...older } = reset;
    for (const body of [older, { ...reset, before_label: null, after_label: null, note: null }]) {
      const row = decode(field, { ...body, before: "listen", after: "connect" });
      if (!row.ok) throw row.error;
      expect(`${beforeText(row.value)} → ${afterText(row.value)}`).toBe("listen → connect");
    }
  });
});
