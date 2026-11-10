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
});
