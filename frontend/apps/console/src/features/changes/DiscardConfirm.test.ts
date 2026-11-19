import { mount } from "@vue/test-utils";
import { nextTick } from "vue";
import { afterEach, describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import DiscardConfirm from "./DiscardConfirm.vue";
import { change } from "./shapes.ts";

function mine() {
  const r = decode(change, {
    id: "chg_1",
    summary: "Edit",
    author: { kind: "user", id: "u_me", name: "Me" },
    staged_at: "2026-11-16T10:00:00Z",
    source: {},
    state: "staged",
    ops: [],
  });
  if (!r.ok) throw new Error(JSON.stringify(r.error));
  return r.value;
}

afterEach(() => {
  document.body.innerHTML = "";
});

describe("DiscardConfirm (ux 11-16)", () => {
  it("confirms in place on Cancel before discarding", async () => {
    const w = mount(DiscardConfirm, {
      attachTo: document.body,
      props: { changes: [mine()], userId: "u_me", discardAny: false, busy: false },
    });
    const trigger = w.findAll("button").find((b) => b.text() === "Discard mine…");
    await trigger?.trigger("click");
    await nextTick();
    expect(w.text()).toContain("Discard your 1 staged change? They can't be brought back.");
    expect(document.activeElement?.textContent?.trim()).toBe("Cancel");
    expect(w.emitted("discard")).toBeUndefined();
    await w
      .findAll("button")
      .find((b) => b.text() === "Discard 1 change")
      ?.trigger("click");
    expect(w.emitted("discard")).toHaveLength(1);
  });
});
