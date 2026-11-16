import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import ReasonSheet from "./ReasonSheet.vue";

describe("ReasonSheet (ux a11y A1 exception: reason first)", () => {
  it("is described by its consequence sentence, which focus skips", () => {
    const w = mount(ReasonSheet, {
      attachTo: document.body,
      props: {
        title: "Revoke credential",
        sentence: "Bookings with this account stop working now.",
        confirm: "Revoke",
      },
    });
    const id = w.get("dialog").attributes("aria-describedby");
    expect(id).toBeTruthy();
    expect(document.getElementById(id ?? "")?.textContent).toBe(
      "Bookings with this account stop working now.",
    );
    w.unmount();
  });
});
