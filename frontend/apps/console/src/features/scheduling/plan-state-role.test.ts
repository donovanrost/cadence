import { mount, type DOMWrapper } from "@vue/test-utils";
import { afterEach, describe, expect, it } from "vite-plus/test";
import { markPlanAct, settlePlanAct } from "./plan-acts.ts";
import PlanStatePanel from "./PlanStatePanel.vue";

/** a11y B6 (#276, ux): a failure after the person's act is an alert; otherwise it's read politely. */
const draftFailed = {
  kind: "draft_failed",
  message: "The draft finished without a plan.",
} as const;
const drafting = { kind: "drafting", phase: null, startedAt: null } as const;
const stubs = { RouterLink: { template: "<a><slot /></a>" } };
afterEach(settlePlanAct);

describe("PlanStatePanel's failure role", () => {
  const roleOf = (w: { findAll(selector: string): DOMWrapper<Element>[] }) =>
    w
      .findAll("[role]")
      .find((e) => e.text().includes("without a plan"))
      ?.attributes("role");

  it("reads a failed draft politely when the screen opened on it", () => {
    const w = mount(PlanStatePanel, { props: { view: draftFailed }, global: { stubs } });
    expect(roleOf(w)).toBe("status");
  });

  it("alerts a failed draft the person started", async () => {
    const w = mount(PlanStatePanel, { props: { view: drafting }, global: { stubs } });
    markPlanAct();
    await w.setProps({ view: draftFailed });
    expect(roleOf(w)).toBe("alert");
  });

  it("stays polite when a failure just appears, with no act (a background refetch)", async () => {
    const w = mount(PlanStatePanel, { props: { view: drafting }, global: { stubs } });
    await w.setProps({ view: draftFailed });
    expect(roleOf(w)).toBe("status");
  });
});
