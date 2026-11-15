import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import type { OpState } from "@/ui";
import QueueReveal from "./QueueReveal.vue";
import { hiddenParts, hiddenRows, QUEUE_CAP } from "./queueCap.ts";

const rows = (...runs: [OpState, number][]) =>
  runs.flatMap(([state, n]) => Array.from({ length: n }, () => ({ state })));

describe("Now over 100 open (Now.md A2)", () => {
  it("hides nothing at or under the cap", () => {
    expect(QUEUE_CAP).toBe(100);
    expect(hiddenRows(rows(["caution", 100]))).toBeNull();
  });

  it("counts what the cut hides by status; zero counts are left out", () => {
    const h = hiddenRows(rows(["crit", 40], ["caution", 472], ["stale", 300], ["neutral", 188]));
    expect(h).toEqual({ count: 900, crit: 0, caution: 412, other: 488 });
    expect(h && hiddenParts(h).map((p) => p.text)).toEqual(["412 caution", "488 other"]);
  });

  it("names crit only when some is hidden, and tints the button row", () => {
    const items = rows(["crit", 103], ["caution", 409], ["neutral", 488]);
    const w = mount(QueueReveal, { props: { items } });
    expect(w.text()).toBe("Show 900 more·3 crit·409 caution·488 other");
    expect(w.find("button").attributes("aria-label")).toBe(
      "Show 900 more: 3 crit, 409 caution, 488 other",
    );
    expect(w.find("li").classes()).toContain("bg-[var(--apogee-wash-crit)]");
    expect(w.findAll(".ap-mark--crit")).toHaveLength(1);
    void w.find("button").trigger("click");
    expect(w.emitted("reveal")).toHaveLength(1);
    const calm = mount(QueueReveal, { props: { items: rows(["caution", 150]) } });
    expect(calm.find("button").attributes("aria-label")).toBe("Show 50 more: 50 caution");
    expect(calm.find("li").classes()).not.toContain("bg-[var(--apogee-wash-crit)]");
    expect(
      mount(QueueReveal, { props: { items: rows(["crit", 5]) } })
        .find("li")
        .exists(),
    ).toBe(false);
  });
});
