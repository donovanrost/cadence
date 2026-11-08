import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { configStateReader } from "./shapes.ts";

const actor = { kind: "user", id: "u1", name: "Mira K." };
const head = {
  revision: 5,
  kind: "change_set",
  live: true,
  applied_at: "2026-11-08T02:29:00Z",
  applied_by: actor,
  reason: "Block 1 framing",
  summary: null,
  entry_count: 1,
  change_set_id: null,
  rolls_back_to: null,
  approvals: [],
};
const set = (extra: Record<string, unknown> = {}) => ({
  id: "cs5",
  version: 1,
  state: "open",
  base_revision: 5,
  opened_at: "2026-11-08T14:02:00Z",
  opened_by: actor,
  staged_count: 1,
  changes: [
    {
      id: "c1",
      summary: "Svalbard · antenna 2 disabled",
      author: actor,
      staged_at: "2026-11-08T14:02:00Z",
      source: { surface: "stations" },
      state: "staged",
      ops: [
        {
          id: "o1",
          kind: "ground_station",
          entity_id: "gs1",
          action: "update",
          paths: ["a"],
          payload: { x: 1 },
        },
      ],
    },
  ],
  withdrawn: [],
  authors: [actor],
  submitted_by: null,
  submitted_at: null,
  reason: null,
  approval_required: null,
  reviews: [],
  failure: null,
  applied_revision: null,
  ...extra,
});

describe("configStateReader", () => {
  it("decodes head, open set and known capabilities (unknown ones dropped)", () => {
    const result = decode(configStateReader, {
      head,
      change_set: set(),
      permissions: ["config.stage", "config.future_thing"],
    });
    expect(result.ok).toBe(true);
    if (result.ok) expect([...result.value.permissions]).toEqual(["config.stage"]);
  });

  it("accepts a mission with nothing staged", () => {
    expect(decode(configStateReader, { head, change_set: null, permissions: [] }).ok).toBe(true);
  });

  it("rejects an applied set as the current one and a miscounted set", () => {
    expect(
      decode(configStateReader, { head, change_set: set({ state: "applied" }), permissions: [] })
        .ok,
    ).toBe(false);
    expect(
      decode(configStateReader, { head, change_set: set({ staged_count: 2 }), permissions: [] }).ok,
    ).toBe(false);
  });
});
