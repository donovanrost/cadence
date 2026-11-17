import { describe, expect, it } from "vite-plus/test";
import { startReasons } from "./attentionVocab.ts";
import { reasonWords } from "./runtime.ts";

/** U38's reasons share the `reason` field with contact_start (U45, U81 §3), whose row words them. */
describe("mission_runtime reason words", () => {
  it("leaves every contact_start reason to its own row, the claimed port included", () => {
    for (const r of startReasons) expect(reasonWords(r, "boom")).toEqual({ text: null });
    expect(reasonWords("listen_endpoint_claimed", null).text).toBeNull();
  });

  it("words its own reasons", () => {
    expect(reasonWords("runtime_not_running", null).text).toBe(
      "The runtime isn't running. Cadence keeps trying every 30 s.",
    );
    // U91: Cadence's faults say so, and never suggest activating again.
    const TELL =
      "It's a fault in Cadence, not in this mission's setup. Tell the team that runs Cadence for you; nothing in the console fixes it.";
    expect(reasonWords("spec_mismatch", null).text).toBe(TELL);
    expect(reasonWords("reconcile_crashed", "bad model.").text).toBe(
      `Cadence's apply process hit an error: bad model. ${TELL}`,
    );
  });
});
