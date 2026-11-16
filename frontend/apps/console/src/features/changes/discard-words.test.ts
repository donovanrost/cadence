import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { discardConfirm } from "./discard-words.ts";
import { change } from "./shapes.ts";

/** A staged change by `who` (decoded, so it's a real Change). */
function by(id: string, name: string | null) {
  const r = decode(change, {
    id: `chg_${Math.random().toString(36).slice(2, 8)}`,
    summary: "Edit",
    author: { kind: "user", id, name },
    staged_at: "2026-11-16T10:00:00Z",
    source: {},
    state: "staged",
    ops: [],
  });
  if (!r.ok) throw new Error(JSON.stringify(r.error));
  return r.value;
}
const me = "u_me";

describe("Discard confirm words (ux 11-16)", () => {
  it("all yours: names the count and that they can't come back", () => {
    expect(discardConfirm([by(me, "Me"), by(me, "Me"), by(me, "Me")], me, true)).toEqual({
      sentence: "Discard your 3 staged changes? They can't be brought back.",
      action: "Discard 3 changes",
    });
  });

  it("discard all with others' changes names them, past two as 'and N others'", () => {
    const two = [by(me, "Me"), by("u_m", "Mira K."), by("u_t", "Tomás R.")];
    expect(discardConfirm(two, me, true).sentence).toBe(
      "Discard all 3 staged changes? 2 of them are other people's: Mira K., Tomás R. They can't be brought back.",
    );
    const four = [...two, by("u_a", "Ana P."), by("u_b", "Ben O.")];
    expect(discardConfirm(four, me, true).sentence).toBe(
      "Discard all 5 staged changes? 4 of them are other people's: Mira K., Tomás R. and 2 others. They can't be brought back.",
    );
  });

  it("discard mine counts only yours and says whose stay staged", () => {
    expect(discardConfirm([by(me, "Me"), by(me, "Me"), by("u_m", "Mira K.")], me, false)).toEqual({
      sentence: "Discard your 2 staged changes? Mira K.'s 1 change stays staged.",
      action: "Discard 2 changes",
    });
  });

  it("says 'someone' for an author without a name", () => {
    expect(discardConfirm([by(me, "Me"), by("svc_1", null)], me, false).sentence).toBe(
      "Discard your 1 staged change? someone's 1 change stays staged.",
    );
  });
});
