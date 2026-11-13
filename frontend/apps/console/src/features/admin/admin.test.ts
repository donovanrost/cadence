import { describe, expect, it } from "vite-plus/test";
import type { RuntimeRow } from "./api.ts";
import { createdText, runtimeText, slugOf, worstFirst } from "./present.ts";

const row = (name: string, runtime: RuntimeRow["runtime"]): RuntimeRow => ({
  organization: { id: "o", name: "Acme", slug: "acme" },
  mission: { id: name, name, slug: name },
  runtime,
  telemetry_last_received_at: null,
  technical: [],
});
const applied = {
  state: "applied" as const,
  reason: null,
  failure_message: null,
  desired_generation: 8,
  applied_generation: 8,
  since: null,
  applied_at: "2026-11-13T03:00:00Z",
};

describe("admin runtime (Admin.md, U38 words)", () => {
  it("reads applied, not applied with the reason, and unknown", () => {
    expect(runtimeText(applied).text).toBe("APPLIED gen 8");
    expect(
      runtimeText({
        ...applied,
        state: "not_applied",
        reason: "spec_mismatch",
        since: "2026-11-13T23:10:00Z",
      }).text,
    ).toBe("NOT APPLIED since 23:10Z: it needs a configuration fix");
    expect(runtimeText(null)).toEqual({ state: "stale", text: "Not known on this node" });
  });
  it("sorts worst first", () => {
    const rows = [
      row("B", applied),
      row("A", null),
      row("C", { ...applied, state: "not_applied", reason: "apply_failed" }),
    ];
    expect(worstFirst(rows).map((r) => r.mission.name)).toEqual(["C", "A", "B"]);
  });
});

describe("create organization (Admin.md)", () => {
  it("fills the slug from the name", () => {
    expect(slugOf("Acme Space — Ops!")).toBe("acme-space-ops");
  });
  it("says both facts when the invite didn't go out", () => {
    const base = { organization: { name: "Acme Space" }, invitation_error: null };
    expect(
      createdText({ ...base, invitation: { email: "ana@acme.space", delivery: "submitted" } }).text,
    ).toBe("Created Acme Space. Invitation sent to ana@acme.space.");
    expect(
      createdText({ ...base, invitation: null, invitation_error: "the email is invalid" }).tone,
    ).toBe("caution");
  });
});
