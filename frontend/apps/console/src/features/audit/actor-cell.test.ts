import { describe, expect, it } from "vite-plus/test";
import { auditActorCell } from "./actor-cell.ts";
import type { AuditEvent } from "./api.ts";

/** U25 (#308) and #470/#523 (ux): the Audit table's actor cell. */
const row = (over: Partial<AuditEvent>): AuditEvent => ({
  id: "e1",
  at: "2026-11-20T03:40:00Z",
  actor: { kind: "user", id: null, name: null },
  kind: "platform",
  action: "Entered admin mode",
  target: null,
  mission: null,
  reason: null,
  subject: undefined,
  admin_mode: undefined,
  change: undefined,
  ...over,
});
const TEAM = { text: "The team that runs Cadence", muted: true, service: false };

describe("the Audit actor cell", () => {
  it("names a nameless person on a platform entry as the team that runs Cadence, muted", () => {
    expect(auditActorCell(row({}))).toEqual(TEAM);
  });

  it("keys on the entry's kind, never the action: elsewhere a nameless person is 'Not known'", () => {
    expect(auditActorCell(row({ kind: "access", action: "Entered admin mode" }))).toEqual({
      text: "Not known",
      muted: true,
      service: false,
    });
  });

  it("keeps named people, services and the system actor on a platform entry", () => {
    expect(auditActorCell(row({ actor: { kind: "user", id: "u1", name: "Mira K." } }))?.text).toBe(
      "Mira K.",
    );
    expect(auditActorCell(row({ actor: { kind: "service", id: "s1", name: null } }))).toEqual({
      text: "Not known",
      muted: true,
      service: true,
    });
    expect(auditActorCell(row({ actor: { kind: "system", id: null, name: null } }))?.text).toBe(
      "Cadence",
    );
  });

  it("is null with no actor at all (the table says 'Not recorded')", () => {
    expect(auditActorCell(row({ actor: null }))).toBeNull();
  });
});
