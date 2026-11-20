import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { previewReader } from "@/features/changes/index.ts";
import {
  dryRunLines,
  profileCard,
  rolloutCancels,
  rolloutKeeps,
  rolloutMoves,
  rolloutOps,
  stageLabel,
  type RolloutProfile,
} from "./rollout.ts";

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

describe("C3 dry-run counts", () => {
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

describe("C3 words", () => {
  const block1: RolloutProfile = {
    id: "prof_1",
    name: "Earendil Block 1",
    current_revision: { id: "cat_14", number: 14, label: "rev 14" },
    spacecraft_count: 500,
    on_current_version: 1,
    on_older_versions: 499,
    override_pinned: 0,
    already_on_revision: 0,
    moves_default: 1,
    moves_all: 500,
  };

  it("names a profile card and the primary by the choice", () => {
    expect(profileCard(block1)).toBe("Earendil Block 1 · 500 spacecraft · rev 14");
    expect(profileCard({ ...block1, current_revision: null })).toBe(
      "Earendil Block 1 · 500 spacecraft · catalog set per spacecraft",
    );
    const one = { kind: "profiles", profiles: [{ id: "prof_1", allVersions: false }] } as const;
    expect(stageLabel(15, one, ["Earendil Block 1"])).toBe("Stage rev 15 for Earendil Block 1");
    expect(
      stageLabel(
        15,
        { kind: "profiles", profiles: [one.profiles[0], { id: "p2", allVersions: false }] },
        [],
      ),
    ).toBe("Stage rev 15 for 2 profiles");
    expect(stageLabel(15, { kind: "spacecraft", ids: ["a", "b", "c"], reason: "x" }, [])).toBe(
      "Stage rev 15 for 3 spacecraft",
    );
  });

  it("reads the dry run as ux's lines", () => {
    expect(preview.ok).toBe(true);
    if (!preview.ok) return;
    expect(dryRunLines(preview.value, { id: "cat_15", number: 15 }, "rev 14", 12)).toEqual([
      { tone: "nominal", text: "Moves 2 spacecraft to rev 15." },
      { tone: "nominal", text: "2 keep rev 14: they're on an older version of the profile." },
      { tone: "nominal", text: "1 keeps its own catalog (override)." },
      { tone: "nominal", text: "1 stays as it is." },
      { tone: "nominal", text: "12 have no profile, so this doesn't reach them." },
      { tone: "caution", text: "Cancels 2 queued commands." },
    ]);
  });
});
