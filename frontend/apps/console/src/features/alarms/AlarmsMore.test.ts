import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import AlarmsMore from "./AlarmsMore.vue";

const props = {
  shown: 200,
  total: 1204,
  what: "active alarms on EARENDIL-008",
  busy: false,
  failed: false,
};

describe("AlarmsMore (#827)", () => {
  it("says how many are shown of how many, so a part never looks like the whole", () => {
    const w = mount(AlarmsMore, { props });
    expect(w.text()).toContain("Showing 200 of 1,204 active alarms on EARENDIL-008, worst first");
  });

  it("Load more asks for the next page, and waits while one is on its way", async () => {
    const w = mount(AlarmsMore, { props });
    await w.get("button").trigger("click");
    expect(w.emitted("more")).toHaveLength(1);

    const busy = mount(AlarmsMore, { props: { ...props, busy: true } });
    expect(busy.get("button").attributes("aria-disabled")).toBe("true");
  });

  it("a failed Load more is an alert beside the button; the alert is always mounted", () => {
    const quiet = mount(AlarmsMore, { props });
    expect(quiet.get('[role="alert"]').text()).toBe("");

    const failed = mount(AlarmsMore, { props: { ...props, failed: true } });
    expect(failed.get('[role="alert"]').text()).toBe(
      "More alarms couldn't load. Try Load more again.",
    );
  });
});
