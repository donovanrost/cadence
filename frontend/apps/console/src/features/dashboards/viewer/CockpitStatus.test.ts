import { mount } from "@vue/test-utils";
import { computed, defineComponent, h, ref } from "vue";
import { describe, expect, it } from "vite-plus/test";
import type { FleetPostureCounts } from "@/shell";
import { provideFleetPosture } from "@/shell/fleet-posture.ts";
import CockpitStatus from "./CockpitStatus.vue";

const posture = (over: Partial<FleetPostureCounts> = {}): FleetPostureCounts => ({
  critical: 2,
  caution: 1,
  stale: 0,
  nominal: 497,
  never_heard: 0,
  total: 500,
  limits_configured: true,
  telemetry: "ok",
  observed_at: "2026-11-26T15:00:00Z",
  ...over,
});

/** Mounts the cockpit under a shell that provides `value` as the /counts posture. */
function cockpit(value: FleetPostureCounts | null | undefined, words = false) {
  const current = ref(value);
  const Shell = defineComponent({
    setup() {
      provideFleetPosture(computed(() => current.value));
      return () => h(CockpitStatus, { words });
    },
  });
  return mount(Shell, { global: { stubs: { RouterLink: { template: "<a><slot /></a>" } } } });
}

/** #847: the cockpit reads the shell's /counts posture, never the fleet's rows. */
describe("CockpitStatus", () => {
  it("shows the posture's crit and caution counts", () => {
    const text = cockpit(posture()).text();
    expect(text).toContain("2");
    expect(text).toContain("1");
  });

  it("says ground limits are off from the posture's limits_configured", () => {
    expect(cockpit(posture({ limits_configured: false }), true).text()).toContain(
      "Ground limits off",
    );
  });

  it("shows nothing until /counts has answered (U20)", () => {
    expect(cockpit(undefined).find("a").exists()).toBe(false);
    expect(cockpit(null).find("a").exists()).toBe(false);
  });

  it("says Fleet nominal only in the phone's words form", () => {
    const calm = posture({ critical: 0, caution: 0, nominal: 500 });
    expect(cockpit(calm, true).text()).toContain("Fleet nominal");
    expect(cockpit(calm, false).text()).not.toContain("Fleet nominal");
  });
});
