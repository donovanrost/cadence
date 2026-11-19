import { describe, expect, it } from "vite-plus/test";
import type { ResolutionAction } from "./attention.ts";
import { decode } from "@/api/index.ts";
import { actionQueueReader, presentQueue } from "./actionQueue.ts";
import { attentionReader, passChangeReader, resolvedWords } from "./attention.ts";
import { fieldLabel, historyEntry, valueWords } from "./providerChange.ts";

/** §11 L14 provider changes (api 30b3f60b9; ux U44), decoded as api sends them. */
const NOW = new Date("2026-11-13T02:20:00Z");
const fieldOf = (field: string, before: unknown, after: unknown) => ({
  field,
  label: null,
  before_json: JSON.stringify(before),
  after_json: JSON.stringify(after),
});
const change = (conflict: string, o: Record<string, unknown> = {}) => ({
  id: `attention:provider_change:chg-1`,
  priority: conflict === "approval_required" ? 2 : 3,
  kind: "attention",
  state: conflict === "approval_required" ? "caution" : "off",
  source: "provider_change",
  acknowledged: null,
  since: null,
  due_at: null,
  count: 1,
  spacecraft: [],
  point: null,
  condition: null,
  plane: null,
  command: null,
  outcome: null,
  command_requests: [],
  finding: null,
  attention: {
    id: "chg-1",
    source: "provider_change",
    conflict,
    state: "open",
    acknowledged_by: null,
    contact_id: "ct-1",
    reservation_id: "res-1",
    station: { ref: "svb", id: "st-1", code: "SVA", name: "Svalbard" },
    provider: { id: "nl", name: "Northlight" },
    starts_at: "2026-11-13T03:10:00Z",
    raised_at: "2026-11-13T02:00:00Z",
    provider_message: null,
    resolution: null,
    deadline_at: "2026-11-13T02:40:00Z",
    provider_change: {
      id: "chg-1",
      classification: conflict === "configuration_failure" ? "configuration_failure" : conflict,
      state: conflict === "approval_required" ? "pending_approval" : "acknowledgment_required",
      deadline_at: "2026-11-13T02:40:00Z",
      provider_revision: 4,
      proposal_hash: "h-1",
      already_effective: conflict !== "approval_required",
      fields: [
        fieldOf("starts_at", "2026-11-13T03:10:00Z", "2026-11-13T03:12:00Z"),
        fieldOf("antenna_or_service_pool_ref", "ant-2", "ant-4"),
        fieldOf("delivery_profile_ref", null, "dp-9"),
        fieldOf("pass_phase", "scheduled", "scheduled"),
        // JSON text from the server: a 64-bit value must survive (contacts.md).
        { field: "brand_new_thing", label: null, before_json: "9007199254740993", after_json: "1" },
      ],
    },
    ...o,
  },
});
const rowOf = (conflict: string, o: Record<string, unknown> = {}) => {
  const r = decode(actionQueueReader, {
    observed_at: NOW.toISOString(),
    stale_after_s: 900,
    failure_lookback_s: 86400,
    counts: { p1: 0, p2: 1, p3: 0, spacecraft_p1: 0 },
    items: [{ ...change(conflict, o), spacecraft: [] }],
  });
  if (!r.ok) throw new Error(r.error.message);
  return presentQueue(r.value, NOW, "EARENDIL")[0];
};

describe("provider changes in Now (U44)", () => {
  it("asks for a decision before the deadline, listing three changes then 'and N more'", () => {
    const row = rowOf("approval_required");
    expect(row?.title).toBe("Spacecraft · Northlight wants to change the SVA 03:10Z pass");
    expect(row?.sentence).toBe(
      "AOS 03:10Z → 03:12Z · Antenna ant-2 → ant-4 · Delivery profile none → dp-9 · and 2 more. Decide by 02:40Z.",
    );
    expect(row?.due).toEqual({ label: "Decide", at: "2026-11-13T02:40:00Z" });
    expect(row?.action).toEqual({
      label: "Review",
      to: { name: "ops.contacts", query: { contact: "res-1" } },
    });
  });

  it("past the deadline: no countdown, and says so (api 84f58b73d; U44)", () => {
    const r = decode(actionQueueReader, {
      observed_at: "2026-11-13T03:00:00Z",
      stale_after_s: 900,
      failure_lookback_s: 86400,
      counts: { p1: 0, p2: 0, p3: 1, spacecraft_p1: 0 },
      items: [change("approval_required")],
    });
    if (!r.ok) throw new Error(r.error.message);
    const row = presentQueue(r.value, new Date("2026-11-13T03:00:00Z"), "EARENDIL")[0];
    expect(row?.due).toBeUndefined();
    expect(row?.sentence).toMatch(/· and 2 more\. The deadline passed at 02:40Z\.$/);
  });

  it("words an applied change and Cadence's own failure", () => {
    const ack = rowOf("acknowledgment_required");
    expect(ack?.title).toBe("Spacecraft · Northlight changed the SVA 03:10Z pass");
    expect(ack?.sentence).toMatch(/Northlight already made this change\.$/);
    expect(ack?.due).toBeUndefined();
    expect(rowOf("configuration_failure")?.title).toBe(
      "Spacecraft · Cadence couldn't apply Northlight's change to the SVA 03:10Z pass",
    );
  });

  it("says who decided, when and why; a newer change replaces it", () => {
    const closed = (action: ResolutionAction, note: string | null) =>
      resolvedWords(
        {
          id: "attention:provider_change:chg-1",
          resolved_by: { kind: "user", id: "u-1", name: "Mira K." },
          action,
          resolved_at: "2026-11-13T02:31:00Z",
          note,
        },
        NOW,
      );
    expect(closed("approved", "The new start still clears the eclipse.")).toBe(
      "Approved by Mira K. at 02:31Z: The new start still clears the eclipse.",
    );
    expect(closed("rejected", null)).toBe("Rejected by Mira K. at 02:31Z.");
    expect(closed("superseded", null)).toBe("Replaced by a newer change.");
  });
});

describe("provider change values (U44)", () => {
  it("never shows JSON quoting; keeps 64-bit numbers; unknown keys read in sentence case", () => {
    const r = decode(attentionReader, change("approval_required").attention);
    if (!r.ok) throw new Error(r.error.message);
    const [start, , delivery, , big] = r.value.provider_change?.fields ?? [];
    if (!start || !delivery || !big) throw new Error("fields");
    expect(valueWords(start, start.after_json, NOW)).toBe("03:12Z");
    expect(valueWords(delivery, delivery.before_json, NOW)).toBe("none");
    expect(valueWords(delivery, delivery.after_json, NOW)).toBe("dp-9");
    expect(valueWords(big, big.before_json, NOW)).toBe("9007199254740993");
    expect(fieldLabel(big)).toBe("Other");
  });
});

describe("a pass's change history (api, L14 flown passes)", () => {
  it("reads every state, the resolution and an unknown state", () => {
    const entry = (state: string, resolution: unknown = null) => ({
      ...change("approval_required").attention.provider_change,
      state,
      raised_at: "2026-11-13T02:00:00Z",
      resolution,
    });
    const approved = decode(
      passChangeReader,
      entry("approved", {
        action: "approved",
        by: { id: "u-1", name: "Mira K." },
        at: "2026-11-13T02:31:00Z",
        reason: "Clears the eclipse.",
      }),
    );
    expect(approved.ok && approved.value.resolution?.by?.name).toBe("Mira K.");
    const expired = decode(passChangeReader, entry("expired"));
    expect(expired.ok && expired.value.state).toBe("expired");
    const later = decode(passChangeReader, entry("brand_new_state"));
    expect(later.ok && later.value.state).toEqual({ unrecognized: "brand_new_state" });
  });
});

describe("pass change history words (ux U44)", () => {
  const entryOf = (state: string, resolution: unknown = null) => {
    const r = decode(passChangeReader, {
      ...change("approval_required").attention.provider_change,
      fields: [fieldOf("starts_at", "2026-11-13T03:10:00Z", "2026-11-13T03:12:00Z")],
      state,
      raised_at: "2026-11-13T02:00:00Z",
      resolution,
    });
    if (!r.ok) throw new Error(r.error.message);
    return historyEntry(r.value, "Northlight", NOW);
  };
  it("leads with the evidence, then the outcome", () => {
    const approved = entryOf("approved", {
      action: "approved",
      by: null,
      at: "2026-11-13T02:31:00Z",
      reason: "Clears the eclipse.",
    });
    expect(approved.evidence).toBe("Northlight changed this pass: AOS 03:10Z → 03:12Z.");
    expect(approved.outcome).toBe("Approved by an operator at 02:31Z: Clears the eclipse.");
    expect(entryOf("policy_accepted").outcome).toBe("Accepted by the mission's policy at 02:00Z.");
    expect(entryOf("superseded").outcome).toBe("Replaced by a newer change.");
    expect(entryOf("expired")).toMatchObject({
      outcome: "Not decided: the pass ended first.",
      expired: true,
    });
    expect(entryOf("apply_failed")).toMatchObject({
      outcome: "Cadence couldn't apply it.",
      crit: true,
    });
  });
  it("keeps open states' blocks; observed and unknown states show the evidence alone", () => {
    expect(entryOf("pending_approval").open).toBe("approval_required");
    expect(entryOf("acknowledgment_required").open).toBe("acknowledgment_required");
    expect(entryOf("observed").outcome).toBeNull();
    expect(entryOf("brand_new").outcome).toBeNull();
  });
});
