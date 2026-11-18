import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { diffEdits, schemaFieldReader, type KindSchema } from "@/features/changes/index.ts";
import { CODE_HELP, codeSuggestion, withCodeRule } from "./code-field.ts";

/** The ground_station schema as served before domain's U25 change (code required: true). */
function schema(): KindSchema {
  const field = (path: string, label: string) => {
    const r = decode(schemaFieldReader, {
      path,
      label,
      type: "string",
      unit: null,
      enum: null,
      range: null,
      default: null,
      required: true,
      help: null,
      visible_when: null,
    });
    if (!r.ok) throw new Error(JSON.stringify(r.error));
    return r.value;
  };
  return { kind: "ground_station", fields: [field("display_name", "Name"), field("code", "Code")] };
}
const codeOf = (s: KindSchema) => s.fields.find((f) => f.path === "code");
const named = (code: string) => ({ display_name: "Inuvik", code });

describe("station Code (ux U25)", () => {
  it("is optional, with the name-fallback help, while no code is stored", () => {
    for (const stored of [null, ""]) {
      const s = withCodeRule(stored)(schema());
      expect(codeOf(s)).toMatchObject({ required: false, help: CODE_HELP });
      expect(s.fields.find((f) => f.path === "display_name")?.required).toBe(true);
      // Left empty, nothing is staged for it.
      expect(diffEdits(s, named(""), named(""))).toEqual({ ok: true, changes: [] });
    }
  });

  it("is required once set, so it can be changed but not emptied", () => {
    const s = withCodeRule("INU")(schema());
    expect(codeOf(s)?.required).toBe(true);
    expect(diffEdits(s, named("INU"), named("")).ok).toBe(false);
    expect(diffEdits(s, named("INU"), named("INV"))).toEqual({
      ok: true,
      changes: [{ path: "code", value: "INV" }],
    });
  });

  it("offers the read's suggested code, and nothing without one", () => {
    expect(codeSuggestion("INU")).toEqual({ path: "code", value: "INU" });
    expect(codeSuggestion(null)).toBeNull();
    expect(codeSuggestion(undefined)).toBeNull();
  });
});
