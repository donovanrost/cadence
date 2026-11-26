import { mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import OutcomeCallout from "./OutcomeCallout.vue";
import { outcomeRole } from "./outcome-role.ts";

describe("outcomeRole (a11y B6, #276)", () => {
  it("reads a success politely and alerts anything that went wrong", () => {
    expect(outcomeRole("nominal")).toBe("status");
    expect(outcomeRole("info")).toBe("status");
    expect(outcomeRole("caution")).toBe("alert");
    expect(outcomeRole("crit")).toBe("alert");
  });
});

describe("OutcomeCallout", () => {
  afterEach(() => {
    vi.useRealTimers();
    document.body.innerHTML = "";
  });

  it("says a success once through the polite region; the callout itself isn't live", () => {
    vi.useFakeTimers();
    const w = mount(OutcomeCallout, { props: { outcome: { tone: "nominal", text: "Approved." } } });
    expect(w.attributes("role")).toBeUndefined();
    vi.advanceTimersByTime(1000); // past announcePolite's short delay
    expect(document.querySelector("[data-ap-announcer]")?.textContent).toBe("Approved.");
  });

  it("makes anything that went wrong an alert, and says nothing extra", () => {
    vi.useFakeTimers();
    const w = mount(OutcomeCallout, {
      props: { outcome: { tone: "caution", text: "Not booked." } },
    });
    expect(w.attributes("role")).toBe("alert");
    vi.advanceTimersByTime(1000); // past announcePolite's short delay
    expect(document.querySelector("[data-ap-announcer]")?.textContent ?? "").not.toBe(
      "Not booked.",
    );
  });

  it("shows the slot's markup and announces outcome.text, the same words (#604)", () => {
    vi.useFakeTimers();
    const w = mount(OutcomeCallout, {
      props: { outcome: { tone: "nominal", text: "2 spacecraft staged as r7." } },
      slots: { default: '2 spacecraft staged as <span class="font-mono">r7</span>.' },
    });
    expect(w.find(".font-mono").text()).toBe("r7");
    vi.advanceTimersByTime(1000);
    expect(document.querySelector("[data-ap-announcer]")?.textContent).toBe(
      "2 spacecraft staged as r7.",
    );
  });
});
