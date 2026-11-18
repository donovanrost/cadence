import { describe, expect, it } from "vite-plus/test";
import type { AuditEvent, AuditPage, AuditQuery } from "./api.ts";
import { allEvents, auditCsv, auditFileName } from "./export.ts";

const event = (id: string): AuditEvent => ({
  id,
  at: "2026-11-12T01:12:07.000Z",
  actor: { kind: "user", id: "u1", name: "Mira K." },
  kind: "config",
  action: "Applied r6 · 2 changes",
  target: { kind: "revision", id: "6", label: "r6" },
  mission: { id: "m1", name: "Earendil" },
  reason: 'Framing "fix", per #45',
  subject: undefined,
  admin_mode: undefined,
  change: undefined,
});
const query: AuditQuery = {
  organizationId: "o1",
  days: 7,
  kinds: [],
  missionId: null,
  to: "2026-11-13T00:00:00.000Z",
};

describe("audit Export CSV", () => {
  it("writes one row per event with words and quoted cells", () => {
    expect(auditCsv([event("e1")]).split("\r\n")).toEqual([
      "Time (UTC),Actor,Actor kind,Kind,Action,Target,Mission,Why,Admin mode,Subject,Subject id,Subject version,Before,After,Missions may override,Mission sets its own",
      '2026-11-12T01:12:07Z,Mira K.,user,Config,Applied r6 · 2 changes,r6,Earendil,"Framing ""fix"", per #45",,,,,,,,',
      "",
    ]);
  });

  it("writes a decision's admin mode and subject (P3 #228, ux): Yes / No, blank when not a decision", () => {
    const decided = {
      ...event("e2"),
      kind: "activations",
      action: "Approved EARENDIL-004 configuration v4",
      subject: { kind: "activation_request", id: "act_9", version: 4 },
      admin_mode: true,
    };
    const lines = auditCsv([decided, { ...decided, admin_mode: false, subject: null }]).split(
      "\r\n",
    );
    expect(lines[1]?.endsWith(",Yes,activation_request,act_9,4,,,,")).toBe(true);
    expect(lines[1]).toContain(",Activations,");
    expect(lines[2]?.endsWith(",No,,,,,,,")).toBe(true);
  });

  it("writes a governance change in the setting's words, never direct/independent (#233, ux U96)", () => {
    const mission = {
      ...event("g1"),
      action:
        "Loosened approval on EARENDIL: Needs a second person's approval → Applies without approval",
      change: {
        before: {
          approval_requirement: "independent" as const,
          override: true,
          allow_override: undefined,
        },
        after: {
          approval_requirement: "direct" as const,
          override: true,
          allow_override: undefined,
        },
      },
    };
    const org = {
      ...mission,
      id: "g2",
      mission: null,
      action: "Missions can no longer set their own approval setting.",
      change: {
        before: {
          approval_requirement: "independent" as const,
          override: undefined,
          allow_override: true,
        },
        after: {
          approval_requirement: "independent" as const,
          override: undefined,
          allow_override: false,
        },
      },
    };
    const [, m, o] = auditCsv([mission, org]).split("\r\n");
    expect(m?.endsWith(",Needs a second person's approval,Applies without approval,,")).toBe(true);
    expect(
      o?.endsWith(",Needs a second person's approval,Needs a second person's approval,No,"),
    ).toBe(true);
    expect(auditCsv([mission, org])).not.toMatch(/direct|independent/);
    // fe-ops/ux: a mission pinning its own value shows in "Mission sets its own", even though
    // Before and After read the same.
    const pin = {
      ...mission,
      id: "g3",
      change: {
        before: {
          approval_requirement: "independent" as const,
          override: false,
          allow_override: undefined,
        },
        after: {
          approval_requirement: "independent" as const,
          override: true,
          allow_override: undefined,
        },
      },
    };
    expect(auditCsv([pin]).split("\r\n")[1]?.endsWith(",,Yes")).toBe(true);
  });
  it("walks every page of the filter", async () => {
    const pages: AuditPage[] = [
      {
        events: [event("e1")],
        sources: { included: [], missing: [] },
        next_cursor: "c2",
        unshown: [{ kind: ["config"], id: "e9" }],
      },
      {
        events: [event("e2")],
        sources: { included: [], missing: [] },
        next_cursor: null,
        unshown: [],
      },
    ];
    const seen: (string | undefined)[] = [];
    const r = await allEvents(query, async (q) => {
      seen.push(q.cursor);
      const page = pages[seen.length - 1];
      if (!page) throw new Error("fixture");
      return { ok: true, value: page };
    });
    expect(r.ok && r.value.events.map((e) => e.id)).toEqual(["e1", "e2"]);
    expect(r.ok && r.value.capped).toBe(false);
    // U86: the dropped event is counted, so the note can say it isn't in the file.
    expect(r.ok && r.value.unshown).toBe(1);
    expect(seen).toEqual([undefined, "c2"]);
  });
  it("names the file by the window's UTC days", () => {
    expect(auditFileName("reflect-orbital", query)).toBe(
      "audit-reflect-orbital-2026-11-06_2026-11-12.csv",
    );
  });
});
