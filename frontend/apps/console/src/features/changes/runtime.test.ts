import { describe, expect, it } from "vite-plus/test";
import type { RuntimeStatus } from "@/shell";
import { configRuntime } from "./runtime.ts";

/** Every optional key present (exactOptionalPropertyTypes). */
const rt = (r: Partial<RuntimeStatus> & { state: string }): RuntimeStatus => ({
  reason: undefined,
  desired_generation: undefined,
  applied_generation: undefined,
  since: undefined,
  applied_at: undefined,
  activated_at: undefined,
  ...r,
});

describe("config runtime after commit (Changes.md §2/§3)", () => {
  it("is applying while a newer generation waits, not applied when it failed", () => {
    expect(
      configRuntime(rt({ state: "applied", desired_generation: 5, applied_generation: 4 })),
    ).toBe("applying");
    expect(configRuntime(rt({ state: "not_applied", reason: "apply_failed" }))).toBe("not_applied");
    expect(
      configRuntime(rt({ state: "not_applied", desired_generation: 6, applied_generation: 5 })),
    ).toBe("applying");
    expect(configRuntime(rt({ state: "not_applied" }))).toBe("not_applied");
  });
  it("says nothing when applied, unknown or unread", () => {
    expect(
      configRuntime(rt({ state: "applied", desired_generation: 5, applied_generation: 5 })),
    ).toBeNull();
    expect(configRuntime(rt({ state: "applied" }))).toBeNull();
    expect(configRuntime(null)).toBeNull();
    expect(configRuntime(undefined)).toBeNull();
  });
});

describe("outcome after Apply (ux, U38 verbs)", async () => {
  const { outcomeRuntime, outcomeText } = await import("./runtime.ts");
  it("prefers the live runtime; a quiet read counts as applied only after it was seen applying", () => {
    expect(outcomeRuntime("converging", undefined, false)).toBe("applying");
    expect(outcomeRuntime("converging", null, false)).toBe("applying");
    expect(outcomeRuntime("converging", null, true)).toBe("applied");
    expect(outcomeRuntime("applied", "not_applied", false)).toBe("not_applied");
    expect(outcomeRuntime("not_applicable", undefined, false)).toBe("none");
  });
  it("reads with 'active' for the config and 'applies' for the runtime", () => {
    expect(outcomeText(6, "2 changes", "applying", null).text).toBe(
      "r6 is active · 2 changes. The runtime is applying it.",
    );
    expect(outcomeText(6, "2 changes", "applied", null).text).toBe(
      "r6 is active and the runtime has applied it · 2 changes.",
    );
    expect(outcomeText(6, "2 changes", "not_applied", "spec_mismatch")).toEqual({
      tone: "caution",
      text: "r6 is active, but the runtime hasn't applied it yet. It needs a fix in Cadence.",
    });
  });
});
