import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { auditReader, kindText } from "./api.ts";

describe("audit kinds the console doesn't know yet", () => {
  it("decodes a new source and labels it from its key", () => {
    const r = decode(auditReader, {
      events: [
        {
          id: "e1",
          at: "2026-11-10T05:00:00Z",
          actor: null,
          kind: "people",
          action: "Accepted an invitation",
          target: null,
          mission: null,
          reason: null,
        },
      ],
      sources: { included: ["config", "people"], missing: ["provider_accounts"] },
      next_cursor: null,
    });
    if (!r.ok) throw r.error;
    expect(r.value.events[0]?.kind).toBe("people");
    expect(kindText("provider_accounts")).toBe("Provider accounts");
    expect(kindText("config")).toBe("Config");
  });

  it("reads the four-eyes record's fields when present, and events without them (P3 #228)", () => {
    const base = {
      at: "2026-11-18T05:00:00Z",
      actor: { kind: "user", id: "u2", name: "Ana R." },
      action: "Approved change set v3",
      target: { kind: "change_set", id: "cs_3", label: "Change set v3" },
      mission: { id: "m1", name: "Earendil" },
      reason: null,
    };
    const r = decode(auditReader, {
      events: [
        {
          ...base,
          id: "a",
          kind: "config",
          subject: { kind: "change_set", id: 3, version: 3 },
          admin_mode: true,
        },
        { ...base, id: "b", kind: "activations", subject: null, admin_mode: null },
        { ...base, id: "c", kind: "provider_changes" },
      ],
      sources: { included: ["config"], missing: [] },
      next_cursor: null,
    });
    if (!r.ok) throw r.error;
    expect(r.value.unshown).toEqual([]);
    expect(
      r.value.events.map((e) => [e.subject?.id ?? null, e.subject?.version ?? null, e.admin_mode]),
    ).toEqual([
      ["3", 3, true],
      [null, null, null],
      [null, null, undefined],
    ]);
    // ux U89: the two new sources' chips.
    expect(kindText("activations")).toBe("Activations");
    expect(kindText("provider_changes")).toBe("Provider changes");
  });
});

describe("sourcePhrase", () => {
  it("reads known kinds as '<kind> events' and provider accounts as changes", async () => {
    const { sourcePhrase } = await import("./api.ts");
    expect(sourcePhrase("config")).toBe("config events");
    expect(sourcePhrase("provider_accounts")).toBe("provider account changes");
    expect(sourcePhrase("people")).toBe("people events");
  });
});
