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

  it("reads an unclear outcome as caution, as an alert, and adds a surface's words and buttons after the link", () => {
    const w = mount(FailureOutcomeCallout, {
      props: { outcome: { changed: null, sentence: "The connection dropped." } },
      slots: { default: "Your draft is kept.", action: "<button>Retry</button>" },
      global: { stubs },
    });
    expect(w.text()).toContain("The connection dropped. Your draft is kept.");
    // a11y B6 (#276, ux): unclear needs the person to check before trying again, so an alert.
    expect(w.find("[role=alert]").exists()).toBe(true);
    expect(w.find("a").exists()).toBe(false);
    expect(w.find("button").text()).toBe("Retry");
  });

  it("underlines the in-use list's links, so they aren't marked by colour alone (#244, C)", () => {
    const w = mount(FailureOutcomeCallout, {
      props: {
        outcome: {
          changed: false,
          sentence: "Not archived.",
          uses: [
            {
              label: "Used by",
              items: [
                { text: "EARENDIL-1", to: { name: "setup.spacecraft" } },
                { text: "A route" },
              ],
              more: 0,
            },
          ],
        },
      },
      global: {
        stubs: { RouterLink: { props: ["to"], template: "<a :class='$attrs.class'><slot /></a>" } },
      },
    });
    const link = w.findAll("a").find((a) => a.text() === "EARENDIL-1");
    expect(link?.classes()).toContain("underline");
    expect(link?.classes()).not.toContain("no-underline");
  });
});
