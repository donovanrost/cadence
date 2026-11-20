import { mount, type DOMWrapper } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import ApRemote from "./ApRemote.vue";
import type { RemoteState } from "./remote-state.ts";

/** a11y B6 (#276, ux): a first load's failure is read politely; after the person's Retry, an alert. */
const failed: RemoteState<string> = {
  status: "failed",
  error: { kind: "network", message: "offline" },
} as RemoteState<string>;
const ready: RemoteState<string> = { status: "ready", value: "x", receivedAt: new Date(0) };

describe("ApRemote's failure role", () => {
  const roleOf = (w: { findAll(selector: string): DOMWrapper<Element>[] }) =>
    w
      .findAll("[role]")
      .find((e) => e.text().includes("Retry"))
      ?.attributes("role");

  it("is polite on load, an alert after Retry, polite again once a load succeeds", async () => {
    const w = mount(ApRemote, { props: { state: failed } });
    expect(roleOf(w)).toBe("status");
    await w.get("button").trigger("click");
    expect(w.emitted("retry")).toHaveLength(1);
    expect(roleOf(w)).toBe("alert");
    await w.setProps({ state: ready });
    await w.setProps({ state: failed });
    expect(roleOf(w)).toBe("status");
  });

  it("is an alert when the screen says the load follows the person's act", () => {
    const w = mount(ApRemote, { props: { state: failed, acted: true } });
    expect(roleOf(w)).toBe("alert");
  });
});
