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
      "Time (UTC),Actor,Actor kind,Kind,Action,Target,Mission,Why",
      '2026-11-12T01:12:07Z,Mira K.,user,Config,Applied r6 · 2 changes,r6,Earendil,"Framing ""fix"", per #45"',
      "",
    ]);
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
