import { describe, expect, it } from "vite-plus/test";
import { fetchPlatformAudit, tokenFailure } from "./api.ts";

/** qa's L7 run (11-13): a 2xx the console can't read, and one bad audit row. */
describe("platform admin readers", () => {
  it("keeps the audit page when one event can't be read, and a null target label", async () => {
    const good = {
      id: "e1",
      at: "2026-11-13T15:00:00Z",
      actor: null,
      action: "Revoked a service identity",
      target: { kind: "service_identity", id: "svc_1", label: null },
      organization: null,
    };
    const original = globalThis.fetch;
    globalThis.fetch = async () =>
      new Response(
        JSON.stringify({
          data: {
            events: [good, { id: "e2", at: 7, target: { kind: "service_identity" } }],
            next: null,
          },
        }),
        {
          status: 200,
        },
      );
    try {
      const r = await fetchPlatformAudit({ after: null }, new AbortController().signal);
      expect(r.ok && r.value.events.map((e) => ("unreadable" in e ? "unreadable" : e.id))).toEqual([
        "e1",
        "unreadable",
      ]);
      const bad = r.ok ? r.value.events[1] : undefined;
      expect(bad && "raw" in bad ? bad.raw : null).toEqual([
        { label: "kind", value: "service_identity" },
        { label: "id", value: "e2" },
      ]);
    } finally {
      globalThis.fetch = original;
    }
  });

  it("says an issue or rotate went through when only its token couldn't be read", () => {
    const malformed = { kind: "malformed" as const, message: "x" };
    expect(tokenFailure(malformed, "issue")).toBe(
      "Issued, but the token couldn't be shown. Rotate it to get a new one.",
    );
    expect(tokenFailure(malformed, "rotate")).toBe(
      "Rotated, but the new token couldn't be shown. The old token no longer works. Rotate it again to get one.",
    );
  });
});
