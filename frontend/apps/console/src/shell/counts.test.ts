import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { countsReader } from "./counts.ts";

describe("counts contract", () => {
  it("accepts the documented payload with nulls for what can't be computed", () => {
    const result = decode(countsReader, {
      observed_at: "2026-11-08T02:41:17Z",
      alarms: { active: 4, critical: 3, caution: 1, unacknowledged: 2, limits_configured: true },
      commands: { open: 25, awaiting_viewer: 2 },
      fleet: { total: 500 },
      contacts: null,
    });
    expect(result.ok).toBe(true);
  });

  it("rejects a fractional count", () => {
    const result = decode(countsReader, {
      observed_at: "2026-11-08T02:41:17Z",
      alarms: null,
      commands: { open: 2.5, awaiting_viewer: 0 },
      fleet: null,
      contacts: null,
    });
    expect(result.ok).toBe(false);
  });
});
