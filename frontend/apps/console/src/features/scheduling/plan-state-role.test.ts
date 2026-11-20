import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import PlanStatePanel from "./PlanStatePanel.vue";

/** a11y B6 (#276, ux): a failure the person watched happen is an alert; one opened on, polite. */
const draftFailed = {
  kind: "draft_failed",
  message: "The draft finished without a plan.",
} as const;
const stubs = { RouterLink: { template: "<a><slot /></a>" } };

describe("PlanStatePanel's failure role", () => {
  const roleOf = (w: ReturnType<typeof mount>) =>
    w
      .findAll("[role]")
      .find((e) => e.text().includes("without a plan"))
      ?.attributes("role");

  it("reads a failed draft politely when the screen opened on it", () => {
    const w = mount(PlanStatePanel, { props: { view: draftFailed }, global: { stubs } });
    expect(roleOf(w)).toBe("status");
  });

  it("alerts a failed draft that ends while the person watches", async () => {
    const w = mount(PlanStatePanel, {
      props: { view: { kind: "drafting", startedAt: null, phase: null } as never },
      global: { stubs },
    });
    await w.setProps({ view: draftFailed });
    expect(roleOf(w)).toBe("alert");
  });
});
