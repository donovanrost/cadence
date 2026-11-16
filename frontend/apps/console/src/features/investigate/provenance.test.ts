import { mount, RouterLinkStub } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import { spacecraftRow } from "@/features/fleet/index.ts";
import { episodeFixture } from "@/features/alarms/fixtures.ts";
import AlarmProvenance from "./AlarmProvenance.vue";
import { centredWindow } from "./model.ts";

const sc = spacecraftRow(312);
const detail = (o: Parameters<typeof episodeFixture>[0] = {}) => ({
  ...episodeFixture(o),
  events: [],
});
const view = (episode: ReturnType<typeof detail>) =>
  mount(AlarmProvenance, {
    props: { episode, sc },
    global: { stubs: { RouterLink: RouterLinkStub } },
  });

describe("B1 provenance (ux U71 A7)", () => {
  it("names the ground limit, links to its version and to the sample that raised it", () => {
    const w = view(
      detail({
        limit_definition_id: "def-1",
        limit_definition_version: 3,
        limit_set_name: "DEFAULT",
        trigger: {
          sample_id: "s-1",
          sample_type: "telemetry_sample",
          point_id: "EPS.VBAT",
          at: "2026-11-08T02:08:11Z",
          receipt_time: "2026-11-08T02:08:11.250Z",
        },
      }),
    );
    expect(w.text()).toContain("From ground limit v3 in limit set DEFAULT");
    const links = w.findAllComponents(RouterLinkStub);
    expect(links.map((l) => l.text())).toEqual([
      "View limit v3",
      "Show the sample that raised it (02:08:11Z)",
    ]);
    expect(links[0]?.props("to")).toEqual({
      name: "setup.app",
      params: { appKey: "limits", surface: "manage" },
      query: { definition: "def-1", version: "3" },
    });
    expect(links[1]?.props("to")).toMatchObject({
      params: { tab: "telemetry" },
      query: { points: "EPS.VBAT", focus: "EPS.VBAT", at: "2026-11-08T02:08:11Z" },
    });
  });
  it("says the catalog's limits, with no links, for catalog monitoring", () => {
    const w = view(
      detail({
        source: "catalog_monitoring",
        trigger: {
          sample_id: null,
          sample_type: null,
          point_id: "EPS.VBAT",
          at: "2026-11-08T02:08:11Z",
          receipt_time: null,
        },
      }),
    );
    expect(w.text()).toContain("From the catalog's limits");
    expect(w.findAllComponents(RouterLinkStub)).toHaveLength(0);
  });
  it("centres the window on the sample, never past now", () => {
    const now = new Date("2026-11-08T12:00:00Z");
    const at = Date.parse("2026-11-08T02:00:00Z");
    expect(centredWindow("6h", at, now)).toEqual({
      from: at - 3 * 3_600_000,
      to: at + 3 * 3_600_000,
    });
    expect(centredWindow("6h", now.getTime() - 60_000, now).to).toBe(now.getTime());
  });
});
