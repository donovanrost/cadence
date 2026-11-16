import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import { createMemoryHistory, createRouter } from "vue-router";
import { spacecraftId } from "@/api/index.ts";
import ExtraRoutesList from "./ExtraRoutesList.vue";
import { extraRouteLine } from "./overrides.ts";

const inu = { id: "gs-1", code: "INU", name: "Inuvik" };
const sc = spacecraftId("sc-1");

describe("U79 P3 extra-route rows", () => {
  it("words a route by station name and its legs", () => {
    expect(
      extraRouteLine({ station: inu, legs: [{ direction: "downlink", role: "primary" }] }),
    ).toBe("Extra route via Inuvik · downlink primary");
    expect(
      extraRouteLine({
        station: { code: "INU", name: null },
        legs: [
          { direction: "downlink", role: "primary" },
          { direction: "uplink", role: "candidate" },
        ],
      }),
    ).toBe("Extra route via INU · downlink primary, uplink candidate");
    expect(extraRouteLine({ station: null, legs: [] })).toBe("Extra route via a removed station");
  });

  it("lists each route under its spacecraft, linking to that spacecraft's routing, with no actions", async () => {
    const router = createRouter({
      history: createMemoryHistory(),
      routes: [
        {
          path: "/spacecraft/:spacecraftId",
          name: "setup.spacecraft.one",
          component: { render: () => null },
        },
      ],
    });
    const w = mount(ExtraRoutesList, {
      props: {
        routes: [
          {
            spacecraft: { id: sc, name: "EARENDIL-389" },
            route_id: "route-1",
            name: "INU · EARENDIL-389",
            station: inu,
            legs: [{ direction: "downlink", role: "primary" }],
          },
        ],
      },
      global: { plugins: [router] },
    });
    const link = w.get("a");
    expect(link.text()).toBe("EARENDIL-389");
    expect(link.attributes("href")).toBe("/spacecraft/sc-1");
    expect(w.text()).toContain("Extra route via Inuvik · downlink primary");
    expect(w.findAll("button")).toHaveLength(0);
  });
});
