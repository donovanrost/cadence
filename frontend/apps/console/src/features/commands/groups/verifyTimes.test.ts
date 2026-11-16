import { describe, expect, it } from "vite-plus/test";
import { verifyTime, windowEnd } from "./verifyTimes.ts";
import type { VerifierSeries } from "./series.ts";

type T = VerifierSeries["targets"][number];
const target = (o: Partial<T>): T => ({
  spacecraft_id: "sc",
  name: null,
  verifier_state: "pending",
  verifier: undefined,
  timeout_at: null,
  matched_at: null,
  samples: [],
  ...o,
});

describe("verify times (ux U69 A4a)", () => {
  it("words each state with seconds, or nothing without a time", () => {
    expect(verifyTime(target({ timeout_at: "2026-11-16T03:12:30Z" }))).toBe("Verify by 03:12:30Z");
    expect(
      verifyTime(target({ verifier_state: "satisfied", matched_at: "2026-11-16T03:11:58Z" })),
    ).toBe("Verified at 03:11:58Z");
    expect(
      verifyTime(target({ verifier_state: "timed_out", timeout_at: "2026-11-16T03:12:30Z" })),
    ).toBe("Timed out at 03:12:30Z: no matching telemetry");
    expect(verifyTime(target({}))).toBeNull();
    expect(verifyTime(undefined)).toBeNull();
  });
  it("ends the pending count with one deadline or the span", () => {
    const series = (targets: T[]) => ({ targets });
    expect(windowEnd(series([target({ timeout_at: "2026-11-16T03:12:30Z" })]))).toBe(
      " · window closes 03:12:30Z",
    );
    expect(
      windowEnd(
        series([
          target({ timeout_at: "2026-11-16T03:20:00Z" }),
          target({ timeout_at: "2026-11-16T03:12:30Z" }),
        ]),
      ),
    ).toBe(" · windows close 03:12–03:20Z");
    expect(windowEnd(series([target({})]))).toBe("");
  });
});
