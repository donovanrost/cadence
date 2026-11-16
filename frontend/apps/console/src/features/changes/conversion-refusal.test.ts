import { describe, expect, it } from "vite-plus/test";
import type { ApiError } from "@/api";
import { failureOutcome } from "./actions.ts";

/** TEMPORARY with the conversion (9ac6dc8ee): ux U79's conversion_in_progress words, from any stage. */
const refusal = (details: unknown): ApiError => ({
  kind: "conflict",
  code: "conversion_in_progress",
  message: "conversion in progress",
  details,
});

describe("conversion_in_progress (ux U79)", () => {
  it("names the staged batch, says nothing was staged, and links the change set", () => {
    expect(failureOutcome(refusal({ change_set_id: "cs9", batch: 3 }), "staged")).toEqual({
      changed: false,
      sentence:
        "Batch 3 of the route conversion is staged, so other changes can't be staged in this mission until it's applied or discarded.",
      link: { label: "Open change set", to: { name: "setup.changes" } },
    });
  });

  it("words it without a batch number when the server sends none", () => {
    expect(failureOutcome(refusal({ change_set_id: "cs9", batch: null }), "staged").sentence).toBe(
      "The route conversion is staged, so other changes can't be staged in this mission until it's applied or discarded.",
    );
  });
});
