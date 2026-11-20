import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import ChangeRowHead from "./ChangeRowHead.vue";
import { change } from "./shapes.ts";

const CHANGE = {
  id: "chg_1",
  summary: "Rename EARENDIL-12",
  author: { kind: "user", id: "u-1", name: "Mira K." },
  staged_at: "2026-11-19T22:00:00Z",
  source: {},
  state: "staged",
  ops: [],
};

/** #313 K9 (ux §10; a11y B7): Withdraw is the ×, named and titled "Withdraw <change> from r6". */
describe("Withdraw", () => {
  it("shows × and names the change and the revision it would have gone in", () => {
    const r = decode(change, CHANGE);
    if (!r.ok) throw new Error("fixture");
    const w = mount(ChangeRowHead, {
      props: { change: r.value, canWithdraw: true, open: false, busy: false, nextRevision: 6 },
    });
    const b = w.get("[data-withdraw]");
    expect(b.text()).toBe("×");
    expect(b.attributes("aria-label")).toBe("Withdraw Rename EARENDIL-12 from r6");
    expect(b.attributes("title")).toBe("Withdraw Rename EARENDIL-12 from r6");
    expect(b.get("span").attributes("aria-hidden")).toBe("true");
  });
});
