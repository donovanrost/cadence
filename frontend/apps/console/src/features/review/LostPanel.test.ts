import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import type { ReviewRow } from "./api.ts";
import LostPanel from "./LostPanel.vue";

// Only the footer is under test: the table renders its footer slot and nothing else.
const table = { template: "<div><slot name='footer' /></div>" };
const rows = (n: number) =>
  Array.from({ length: n }, (_, i) => ({ id: `pass-${String(i)}` }) as ReviewRow);

function panel(props: Partial<{ failed: boolean; hasMore: boolean; loading: boolean }> = {}) {
  return mount(LostPanel, {
    props: { rows: rows(50), total: 1204, hasMore: true, loading: false, failed: false, ...props },
    global: { stubs: { ApTable: table } },
  });
}

/** R4 on usePagedQuery (#176): the pages shown, Load more, and its failure said as an alert. */
describe("LostPanel's paging footer", () => {
  it("says how many of the matching passes are shown", () => {
    expect(panel().text()).toContain("Showing 50 of 1,204");
  });

  it("offers Load more only while there is a next page", () => {
    expect(panel().find("button").exists()).toBe(true);
    expect(panel({ hasMore: false }).find("button").exists()).toBe(false);
  });

  it("says a failed Load more in an alert that is always mounted", async () => {
    const w = panel();
    expect(w.get("[role=alert]").text()).toBe("");
    await w.setProps({ failed: true });
    expect(w.get("[role=alert]").text()).toBe("More passes couldn't load. Try Load more again.");
  });

  it("shows the empty state, not the footer, when no pass was lost", () => {
    const w = mount(LostPanel, {
      props: { rows: [], total: 0, hasMore: false, loading: false, failed: false },
    });
    expect(w.text()).toContain("No missed or partial passes");
    expect(w.find("[role=alert]").exists()).toBe(false);
  });
});
