import { effectScope, nextTick, ref } from "vue";
import { afterEach, beforeEach, describe, expect, it, vi } from "vite-plus/test";
import type { RuntimeStatus } from "./counts.ts";
import { outageText, RESUMED_MS, resumedText, useRuntimeBanner } from "./runtime-banner.ts";

const down: RuntimeStatus = {
  state: "not_applied",
  reason: "runtime_not_running",
  desired_generation: 8,
  applied_generation: 7,
  since: "2026-11-12T23:11:00Z",
  applied_at: "2026-11-12T20:00:00Z",
  activated_at: "2026-11-12T23:10:00Z",
};
const up: RuntimeStatus = { ...down, state: "applied", applied_at: "2026-11-12T23:26:00Z" };

describe("U38 runtime banner words", () => {
  it("names each time only when the server sends it (U20)", () => {
    expect(outageText(down, "EARENDIL")).toBe(
      "Telemetry isn't being processed for EARENDIL since 23:11Z. The runtime hasn't applied the configuration activated at 23:10Z.",
    );
    expect(outageText({ ...down, activated_at: null }, "EARENDIL")).toBe(
      "Telemetry isn't being processed for EARENDIL since 23:11Z. The runtime hasn't applied the active configuration.",
    );
    expect(outageText({ ...down, since: null, activated_at: null }, "EARENDIL")).toBe(
      "Telemetry isn't being processed for EARENDIL. The runtime hasn't applied the active configuration.",
    );
  });

  it("adds the fix line only where retrying can't clear it (U91: a fix in Cadence)", () => {
    for (const reason of ["spec_mismatch", "reconcile_crashed"] as const)
      expect(outageText({ ...down, reason }, "EARENDIL")).toMatch(
        / at 23:10Z\. It needs a fix in Cadence\.$/,
      );
    for (const reason of ["runtime_not_running", "apply_failed", null] as const)
      expect(outageText({ ...down, reason }, "EARENDIL")).not.toMatch(/needs a fix/);
  });

  it("says resumed only with the server's applied_at", () => {
    expect(resumedText(up)).toBe("Telemetry processing resumed at 23:26Z.");
    expect(resumedText({ ...up, applied_at: null })).toBeNull();
    expect(resumedText(null)).toBeNull();
  });
});

describe("useRuntimeBanner", () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  function mount(initial: RuntimeStatus | null | undefined) {
    const runtime = ref<RuntimeStatus | null | undefined>(initial);
    const mission = ref<string | null>("EARENDIL");
    const scope = effectScope();
    const banner = scope.run(() => useRuntimeBanner(runtime, mission));
    if (!banner) throw new Error("no banner");
    return { runtime, mission, banner, scope };
  }

  it("shows crit while not applied, then nominal for 5 s after this page saw it recover", async () => {
    const { runtime, banner, scope } = mount(down);
    expect(banner.value?.tone).toBe("crit");
    runtime.value = up;
    await nextTick();
    expect(banner.value).toEqual({
      tone: "nominal",
      text: "Telemetry processing resumed at 23:26Z.",
    });
    vi.advanceTimersByTime(RESUMED_MS);
    expect(banner.value).toBeNull();
    scope.stop();
  });

  it("shows nothing on a page opened after recovery", () => {
    const { banner, scope } = mount(up);
    expect(banner.value).toBeNull();
    scope.stop();
  });

  it("keeps the outage up while the counts read fails (undefined), and clears on null", async () => {
    const { runtime, banner, scope } = mount(down);
    runtime.value = undefined;
    await nextTick();
    expect(banner.value?.tone).toBe("crit");
    runtime.value = null;
    await nextTick();
    expect(banner.value).toBeNull();
    scope.stop();
  });

  it("starts over on another mission", async () => {
    const { runtime, mission, banner, scope } = mount(down);
    mission.value = "TINUVIEL";
    runtime.value = up;
    await nextTick();
    expect(banner.value).toBeNull();
    scope.stop();
  });
});
