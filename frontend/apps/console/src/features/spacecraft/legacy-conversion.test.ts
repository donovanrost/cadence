import { describe, expect, it } from "vite-plus/test";
import { decode, type ApiError } from "@/api";
import {
  conversionReader,
  NOT_ADMIN,
  NOTHING_LEFT,
  FAILED,
  progressLine,
  skippedLine,
  skippedSpacecraft,
  stageFailure,
  stageLabel,
  stagedLine,
  type SkippedRoute,
} from "./legacy-conversion.ts";

/** TEMPORARY with the conversion (9ac6dc8ee). Fixtures are api v3.2's wire, through the decoder. */
const conversionWire = (extra: Record<string, unknown> = {}) => ({
  routes_converted: 450,
  routes_total: 1500,
  batch_size: 50,
  batches_total: 10,
  next_batch: 2,
  staged_batch: null,
  unmappable: { count: 0, routes: [] },
  can_stage: true,
  ...extra,
});
const skipped = (name: string | null, id = "sc_389") => ({
  routing_rule_id: `rr_${id}`,
  reason: "transport_has_no_station",
  spacecraft: { id, name },
});
function conversion(extra: Record<string, unknown> = {}) {
  const r = decode(conversionReader, conversionWire(extra));
  if (!r.ok) throw new Error(JSON.stringify(r.error));
  return r.value;
}
const routes = (...wire: object[]): readonly SkippedRoute[] =>
  conversion({ unmappable: { count: wire.length, routes: wire } }).unmappable.routes;
const refusal = (code: string, details: unknown = null): ApiError => ({
  kind: "conflict",
  code,
  message: "refused",
  details,
});

describe("legacy route conversion words (ux U79, api v3.2)", () => {
  it("counts routes converted and labels the next batch", () => {
    const c = conversion();
    expect(progressLine(c)).toBe("450 of 1,500 routes converted.");
    expect(stageLabel(c)).toBe("Stage batch 2 of 10");
    expect(stageLabel(conversion({ next_batch: null }))).toBeNull();
  });

  it("names who staged a batch, and leaves out a nameless one (never an id)", () => {
    expect(stagedLine(3, "Mira K.")).toBe(
      "Batch 3 is staged in Mira K.'s change set. Apply or discard it before staging the next.",
    );
    expect(stagedLine(3, null)).toBe(
      "Batch 3 is already staged. Apply or discard it before staging the next.",
    );
  });

  it("words one skipped route in full and counts several, listing each spacecraft once", () => {
    expect(skippedLine(routes(skipped("EARENDIL-389")))).toBe(
      "1 route wasn't converted: EARENDIL-389's transport has no station. Remove it on that spacecraft's routing page.",
    );
    expect(skippedLine(routes(skipped(null)))).toContain("its transport has no station");
    const three = routes(skipped("A-1", "sc_1"), skipped("A-1", "sc_1"), skipped("B-2", "sc_2"));
    expect(skippedLine(three)).toBe("3 routes weren't converted.");
    expect(skippedSpacecraft(three).map((s) => s.name)).toEqual(["A-1", "B-2"]);
    expect(skippedLine([])).toBeNull();
    // A reason this console doesn't know yet still reads, without a cause.
    expect(skippedLine(routes({ ...skipped("C-3"), reason: "station_retired" }))).toBe(
      "1 route wasn't converted. Remove it on its spacecraft's routing page.",
    );
  });

  it("words each refusal, with Open change set or Try again where ux puts them", () => {
    const already = stageFailure(
      refusal("conversion_already_staged", {
        change_set_id: "cs9",
        batch: 3,
        author: { id: "u1", name: "Mira K." },
      }),
    );
    expect(already).toEqual({
      sentence: stagedLine(3, "Mira K."),
      openSet: true,
      retry: false,
    });
    expect(stageFailure(refusal("open_change_set_not_empty", { change_set_id: "cs9" }))).toEqual({
      sentence:
        "The mission's open change set has other changes. Apply or discard them first, so this batch is reviewed on its own.",
      openSet: true,
      retry: false,
    });
    expect(
      stageFailure({ kind: "invalid", code: "nothing_to_convert", message: "", details: null })
        .sentence,
    ).toBe(NOTHING_LEFT);
    expect(stageFailure({ kind: "forbidden", code: "forbidden", message: "" }).sentence).toBe(
      NOT_ADMIN,
    );
    expect(stageFailure({ kind: "unavailable", status: 503, message: "down" })).toEqual({
      sentence: FAILED,
      openSet: false,
      retry: true,
    });
  });
});
