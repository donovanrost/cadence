import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import type { FailureOutcome } from "./actions.ts";
import FailureOutcomeCallout from "./FailureOutcomeCallout.vue";

const stubs = {
  RouterLink: { props: ["to"], template: "<a :data-to='JSON.stringify(to)'><slot /></a>" },
};
const refused: FailureOutcome = {
  changed: false,
  sentence: "Nothing was staged.",
  link: { label: "Open change set", to: { name: "setup.changes" } },
};

describe("FailureOutcomeCallout (ux, lead 11-16: one failure callout everywhere)", () => {
  it("reads the sentence and puts its link as the action", () => {
    const w = mount(FailureOutcomeCallout, { props: { outcome: refused }, global: { stubs } });
    expect(w.text()).toContain("Nothing was staged.");
    const link = w.find("a");
    expect(link.text()).toBe("Open change set");
    expect(link.attributes("data-to")).toBe(JSON.stringify({ name: "setup.changes" }));
    expect(w.find("[role=alert]").exists()).toBe(true);
  });

  it("reads an unclear outcome as caution, adds a surface's words and buttons after the link", () => {
    const w = mount(FailureOutcomeCallout, {
      props: { outcome: { changed: null, sentence: "The connection dropped." } },
      slots: { default: "Your draft is kept.", action: "<button>Retry</button>" },
      global: { stubs },
    });
    expect(w.text()).toContain("The connection dropped. Your draft is kept.");
    expect(w.find("[role=alert]").exists()).toBe(false);
    expect(w.find("a").exists()).toBe(false);
    expect(w.find("button").text()).toBe("Retry");
  });
});
