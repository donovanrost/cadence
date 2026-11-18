import { describe, expect, it } from "vite-plus/test";
import type { PlanDetail } from "./api.ts";
import { decode, spacecraftId } from "@/api";
import { historyLines, oldVersionLine, planHistoryReader } from "./plan-history.ts";

const plan = (over: Partial<PlanDetail>): PlanDetail => ({
  id: "plan_1",
  version: 41,
  state: "draft",
  window: { from: null, to: null },
  author: null,
  counts: { passes: 12, minutes: 96, conflicts: 0, unsatisfied: 0 },
  ready_to_approve: true,
  updated_at: "2026-11-09T10:00:00Z",
  created_at: null,
  passes: [],
  demand: { rule_met: 3, rule_total: 3, spacecraft: [], rules: [] },
  unmet: [],
  conflicts: [],
  at_risk: [],
  unconfirmed: null,
  chain: null,
  execution: null,
  provider_freeze: null,
  approval: null,
  submission: null,
  previous_round: null,
  chain_head: null,
  superseded: null,
  repair_of: null,
  superseded_by: null,
  latest_version: undefined,
  ...over,
});

const now = new Date("2026-11-13T12:00:00Z");
const actor = (name: string | null, kind = "user") => ({ kind, id: "u1", name });
const history = decode(planHistoryReader, {
  plan_id: "plan_1",
  latest_version: 4,
  versions: [
    {
      version: 4,
      created_at: "2026-11-13T04:00:00Z",
      created_by: actor(null, "system"),
      rationale: null,
      content_sha256: "x",
      selected: 1512,
      locked: 36,
      rejected: 4,
      decision: null,
      submitted: false,
    },
    {
      version: 2,
      created_at: "2026-11-12T02:44:00Z",
      created_by: actor("Maya T."),
      rationale: "Svalbard is down",
      content_sha256: "y",
      selected: 10,
      locked: 0,
      rejected: 1,
      decision: "rejected",
      submitted: true,
    },
  ],
  decisions: [
    {
      kind: "rejected",
      version: 2,
      round: 1,
      actor: actor("Ana R."),
      at: "2026-11-13T02:58:00Z",
      text: "Svalbard is down tonight, re-draft without SVB.",
      unchanged: null,
      acknowledgements: [],
      exceptions: [],
      automation_grant_id: null,
    },
    {
      kind: "submitted",
      version: 2,
      round: 1,
      actor: actor("Maya T."),
      at: "2026-11-13T02:46:00Z",
      text: null,
      unchanged: false,
      acknowledgements: [{ requirement_id: "req_1", reason: "No pass over SVB tonight" }],
      exceptions: [],
      automation_grant_id: null,
    },
    {
      kind: "approved",
      version: 3,
      round: 2,
      actor: null,
      at: "2026-11-13T03:10:00Z",
      text: null,
      unchanged: null,
      acknowledgements: [],
      exceptions: [],
      automation_grant_id: "grant_1",
    },
  ],
  truncated: false,
});

describe("plan history (U73)", () => {
  it("lists versions and decisions newest first in ux's words", () => {
    if (!history.ok) throw new Error(JSON.stringify(history.error));
    const lines = historyLines(history.value, now);
    expect(lines.map((l) => l.line)).toEqual([
      "R4 · drafted by Cadence at 04:00Z",
      "Approved R3 automatically under an automation policy at 03:10Z",
      "Sent back R2 by Ana R. at 02:58Z: “Svalbard is down tonight, re-draft without SVB.”",
      "Submitted R2 for approval by Maya T. at 02:46Z · 1 gap accepted",
      "R2 · drafted by Maya T. at 11-12 02:44Z",
    ]);
    const [current, , , submitted, old] = lines;
    expect(current?.tags.map((t) => t.label)).toEqual(["CURRENT"]);
    expect(current?.view).toBeNull();
    expect(current?.counts).toBe("1,512 selected · 36 locked · 4 rejected");
    expect(old?.tags.map((t) => t.label)).toEqual(["SENT BACK"]);
    expect(old?.view).toBe(2);
    expect(old?.quote).toBe("“Svalbard is down”");
    expect(submitted?.detailsLabel).toBe("Show 1");
    expect(submitted?.details).toEqual([{ id: "req_1", text: "No pass over SVB tonight" }]);
  });

  it("words an older version's callout by its own decision", () => {
    const at = "2026-11-13T02:58:00Z";
    const a = { kind: "user" as const, id: "u2", name: "Ana R." };
    expect(
      oldVersionLine(
        plan({
          version: 2,
          approval: { decision: "rejected", actor: a, at, reason: null, exceptions: [] },
        }),
        4,
        now,
      ),
    ).toBe("You're looking at R2, sent back 02:58Z. The current version is R4.");
    expect(
      oldVersionLine(
        plan({
          version: 2,
          approval: { decision: "approved", actor: a, at, reason: null, exceptions: [] },
        }),
        4,
        now,
      ),
    ).toBe("You're looking at R2, approved 02:58Z and since replaced by R4.");
    expect(oldVersionLine(plan({ version: 2 }), 4, now)).toBe(
      "You're looking at R2, never submitted. The current version is R4.",
    );
  });
});

describe("gap rows with names (api f3aa9b272)", () => {
  it("leads with the spacecraft and requirement, and falls back to the reason", async () => {
    const { gapText } = await import("./plan-history.ts");
    expect(
      gapText({
        requirement_id: "r1",
        reason: "no window can cover it",
        requirement_label: "Block 1 daily",
        spacecraft: { id: spacecraftId("sc"), name: "EARENDIL-389", scid: null },
        requirement_window: undefined,
      }),
    ).toBe("EARENDIL-389 · Block 1 daily: no window can cover it");
    expect(
      gapText({
        requirement_id: "r1",
        reason: "no window can cover it",
        requirement_label: undefined,
        spacecraft: undefined,
        requirement_window: undefined,
      }),
    ).toBe("no window can cover it");
  });
});

describe("gap windows (ux U73, api 3386a8bf3)", () => {
  it("puts the window after the label, dated only off the plan's day", async () => {
    const { gapText } = await import("./plan-history.ts");
    const gap = (from: string, to: string) => ({
      requirement_id: "r1",
      reason: "no window can cover it",
      requirement_label: "Block 1 daily",
      spacecraft: { id: spacecraftId("sc"), name: "EARENDIL-389", scid: null },
      requirement_window: { from, to },
    });
    expect(gapText(gap("2026-11-16T06:00:00Z", "2026-11-16T12:00:00Z"), "2026-11-16")).toBe(
      "EARENDIL-389 · Block 1 daily · 06:00–12:00Z: no window can cover it",
    );
    expect(gapText(gap("2026-11-16T18:00:00Z", "2026-11-17T00:00:00Z"), "2026-11-16")).toBe(
      "EARENDIL-389 · Block 1 daily · 18:00–00:00Z: no window can cover it",
    );
    expect(gapText(gap("2026-11-16T22:00:00Z", "2026-11-17T02:00:00Z"), "2026-11-16")).toBe(
      "EARENDIL-389 · Block 1 daily · 11-16 22:00–11-17 02:00Z: no window can cover it",
    );
  });
});
