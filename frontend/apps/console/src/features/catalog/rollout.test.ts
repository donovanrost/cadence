import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { previewReader } from "@/features/changes/index.ts";
import { rolloutCancels, rolloutKeeps, rolloutMoves, rolloutOps } from "./rollout.ts";

describe("C3 rollout ops", () => {
  it("stages one profile op per profile, all_versions only when asked", () => {
    expect(
      rolloutOps("cat_15", {
        kind: "profiles",
        profiles: [
          { id: "prof_1", allVersions: false },
          { id: "prof_2", allVersions: true },
        ],
      }),
    ).toEqual([
      {
        kind: "spacecraft_profile",
        action: "update",
        entity_id: "prof_1",
        changes: [{ path: "catalog_revision_id", value: "cat_15" }],
      },
      {
        kind: "spacecraft_profile",
        action: "update",
        entity_id: "prof_2",
        changes: [{ path: "catalog_revision_id", value: "cat_15" }],
        options: { rollout: "all_versions" },
      },
    ]);
  });

  it("stages a canary as one catalog override per spacecraft", () => {
    expect(
      rolloutOps("cat_15", { kind: "spacecraft", ids: ["sc_1"], reason: "Canary for rev 15" }),
    ).toEqual([
      {
        kind: "spacecraft_override",
        action: "update",
        entity_id: "sc_1",
        changes: [
          { path: "catalog_revision_id", value: { value: "cat_15", reason: "Canary for rev 15" } },
        ],
      },
    ]);
  });
});

describe("C3 dry-run counts", () => {
  const preview = decode(previewReader, {
    verdict: "hold",
    checks: [
      {
        key: "compatibility",
        verdict: "hold",
        items: [
          {
            kind: "spacecraft",
            reason: "catalog_change",
            spacecraft_ids: ["sc_1", "sc_2"],
            from: "cat_14",
            to: "cat_15",
          },
          { kind: "spacecraft", reason: "catalog_change", spacecraft_ids: ["sc_9"], to: "cat_13" },
          {
            kind: "spacecraft",
            reason: "catalog_cancels_commands",
            spacecraft_ids: [],
            requests: [{ command_request_id: "r1" }, { command_request_id: "r2" }],
          },
        ],
      },
    ],
    effects: [
      {
        op_id: "o1",
        changes: 3,
        keeps: [
          {
            spacecraft: { id: "sc_3", name: "E-3" },
            reason: "stays on v3",
            code: "older_profile_version",
          },
          {
            spacecraft: { id: "sc_4", name: "E-4" },
            reason: "stays on v4",
            code: "older_profile_version",
          },
          {
            spacecraft: { id: "sc_5", name: "E-5" },
            reason: "its own override sets its catalog",
            code: "catalog_override",
          },
          { spacecraft: { id: "sc_6", name: "E-6" }, reason: "something new" },
        ],
      },
    ],
  });

  it("groups the spacecraft that stay by the server's code", () => {
    expect(preview.ok).toBe(true);
    if (!preview.ok) return;
    expect([...rolloutKeeps(preview.value)]).toEqual([
      ["older_profile_version", 2],
      ["catalog_override", 1],
      ["other", 1],
    ]);
  });

  it("counts moves onto this revision and the commands the apply cancels", () => {
    expect(preview.ok).toBe(true);
    if (!preview.ok) return;
    expect(rolloutMoves(preview.value, "cat_15")).toBe(2);
    expect(rolloutCancels(preview.value)).toBe(2);
  });
});
