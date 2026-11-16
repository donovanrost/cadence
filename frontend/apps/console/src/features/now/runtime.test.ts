import { describe, expect, it } from "vite-plus/test";
import { startReasons } from "./attentionVocab.ts";
import { reasonWords } from "./runtime.ts";

/** U38's reasons share the `reason` field with contact_start (U45, U81 §3), whose row words them. */
describe("mission_runtime reason words", () => {
  it("leaves every contact_start reason to its own row, the claimed port included", () => {
    for (const r of startReasons)
      expect(reasonWords(r, "boom")).toEqual({ text: null, needsFix: false });
    expect(reasonWords("listen_endpoint_claimed", null).text).toBeNull();
  });

  it("words its own reasons", () => {
    expect(reasonWords("runtime_not_running", null).text).toBe(
      "The runtime isn't running. Cadence keeps trying every 30 s.",
    );
    expect(reasonWords("spec_mismatch", null).needsFix).toBe(true);
  });
});
