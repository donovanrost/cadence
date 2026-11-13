import { describe, expect, it } from "vite-plus/test";
import { stagedFields, stagedText } from "./staged.ts";

const change = (authorId: string, name: string, entity: string, changes: unknown) => ({
  id: `c-${authorId}`,
  summary: "x",
  author: { kind: "user" as const, id: authorId, name },
  staged_at: "2026-11-13T00:00:00Z",
  source: null,
  state: "staged" as const,
  ops: [
    {
      id: "o1",
      kind: "spacecraft_profile" as const,
      entity_id: entity,
      action: "update" as const,
      paths: [],
      payload: { changes },
    },
  ],
});
const set = (changes: ReturnType<typeof change>[]) => ({ changes });

describe("profile conflict chip (Profile.md States)", () => {
  it("maps this profile's staged paths to who staged them and the value", () => {
    const map = stagedFields(
      set([
        change("u2", "Mira K.", "p1", [{ path: "frame_parameters.frame_size", value: 1200 }]),
        change("u1", "Me", "p1", [{ path: "catalog_revision_id", value: "rev_4" }]),
        change("u2", "Mira K.", "p2", [{ path: "downlink_protocol", value: "aos" }]),
      ]),
      "p1",
      "u1",
    );
    expect([...map.keys()].sort()).toEqual(["catalog_revision_id", "frame_parameters.frame_size"]);
    expect(map.get("frame_parameters.frame_size")).toMatchObject({ by: "Mira K.", mine: false });
    expect(map.get("catalog_revision_id")?.mine).toBe(true);
  });

  it("reads 'Mira K. staged 1,200'", () => {
    const f = {
      path: "frame_parameters.frame_size",
      label: "TM frame length",
      type: "integer" as const,
      unit: null,
      enum: null,
      range: null,
      default: null,
      overridable: true,
      runtime_impact: "generation" as const,
      help: null,
      value: 1115,
      overridden_by: 0,
    };
    expect(stagedText(f, { path: f.path, by: "Mira K.", mine: false, value: 1200 })).toBe(
      "Mira K. staged 1,200",
    );
  });
});
