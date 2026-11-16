import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import { createMemoryHistory, createRouter } from "vue-router";
import HistoryTable from "./HistoryTable.vue";
import { row } from "./testRows.ts";
import type { LedgerItem } from "./useHistory.ts";

function render(items: readonly LedgerItem[], width: "phone" | "mid" | "wide" = "wide") {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [{ path: "/", component: { template: "<div />" } }],
  });
  return mount(HistoryTable, {
    props: {
      items,
      width,
      selectedId: null,
      caption: "Contact history",
      spacecraftName: () => "EARENDIL-312",
    },
    global: { plugins: [router] },
  });
}
const item = (o: Record<string, unknown>): LedgerItem => {
  const r = row(o);
  return { kind: "pass", key: r.id, pass: r };
};

describe("History table (U78)", () => {
  it("a never-live contact shows when it was created, and its link says it never started", () => {
    const defined = item({
      id: "rc-3",
      booked: false,
      state: "defined",
      starts_at: "2026-11-16T02:59:40Z",
    });
    for (const width of ["wide", "phone"] as const) {
      const link = render([defined], width).get("a");
      expect(link.text().replace(/\s+/g, " ")).toBe("Created 11-16 02:59:40Z");
      expect(link.attributes("aria-label")).toBe("Created 11-16 02:59:40Z, never started");
    }
  });

  it("so does one Cadence's sweep closed (stopped, not_started)", () => {
    const swept = item({
      id: "rc-9",
      booked: false,
      state: "stopped",
      not_started: true,
      starts_at: "2026-11-13T02:59:40Z",
      ends_at: "2026-11-13T03:59:40Z",
    });
    const w = render([swept]);
    expect(w.get("a").text().replace(/\s+/g, " ")).toBe("Created 11-13 02:59:40Z");
    expect(w.text()).toContain("Not started");
  });

  it("a hand-started row is tagged and has no reservation, revision or schedule", () => {
    const w = render([
      item({ id: "rc-1", booked: false, state: "active", starts_at: "2026-11-16T02:00:00Z" }),
    ]);
    expect(w.text()).toContain("HAND-STARTED");
    expect(w.text()).toContain("In contact");
    expect(
      w
        .findAll("td")
        .map((td) => td.text())
        .slice(4),
    ).toEqual(["—", "—", "—"]);
  });

  it("a booked pass links its window and has no Created wording", () => {
    const w = render([item({ id: "res-1", starts_at: "2026-11-12T02:59:40Z" })], "mid");
    expect(w.get("a").text()).toBe("11-12 02:59:40 – 03:08:52Z");
    expect(w.get("a").attributes("aria-label")).toBeUndefined();
    expect(w.text()).not.toContain("HAND-STARTED");
  });
});
