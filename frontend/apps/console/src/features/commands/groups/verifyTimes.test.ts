import { describe, expect, it } from "vite-plus/test";
import { groupOf } from "./fixtures.ts";
import { memberVerifyTime, targetVerifyTime, windowEnd } from "./verifyTimes.ts";
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
  it("words the member's own times (api 3438b783c), so transport-only verifiers have them", () => {
    const t = groupOf().targets[0];
    const m = t?.members[0];
    if (!t || !m) throw new Error("fixture");
    const at = (o: Partial<typeof m>) => memberVerifyTime({ ...m, ...o });
    expect(at({ stage: "executed", verify_by: "2026-11-16T03:12:30Z" })).toBe(
      "Verify by 03:12:30Z",
    );
    expect(at({ stage: "verified", verified_at: "2026-11-16T03:11:58Z" })).toBe(
      "Verified at 03:11:58Z",
    );
    expect(at({ stage: "verify_failed", timed_out_at: "2026-11-16T03:12:30Z" })).toBe(
      "Timed out at 03:12:30Z: no matching telemetry",
    );
    expect(at({ stage: "verify_failed", failed_at: "2026-11-16T03:12:04Z" })).toBe(
      "Failed at 03:12:04Z",
    );
    expect(at({ stage: "queued_for_contact", verify_by: null })).toBeNull();
    expect(
      targetVerifyTime({
        ...t,
        stage: "verified",
        members: [{ ...m, stage: "verified", verified_at: "2026-11-16T03:11:58Z" }],
      }),
    ).toBe("Verified at 03:11:58Z");
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
