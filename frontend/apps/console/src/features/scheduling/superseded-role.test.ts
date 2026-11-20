import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import { defineComponent, effectScope, h, nextTick, ref } from "vue";
import { supersededReader } from "./plans-api.ts";
import { useSupersededRole } from "./superseded-role.ts";
import SupersededCallout from "./SupersededCallout.vue";

/** #654 (a11y B6): the superseded line is an alert only right after the person's refused Submit. */
const superseded = supersededReader(
  {
    at: "2026-11-20T09:12:00Z",
    by: { kind: "user", id: "u-1", name: "Mira K." },
    reason: "requirement_changed",
    changes: [],
  },
  "",
);

describe("SupersededCallout's role (#654)", () => {
  it("is polite by default (found superseded on load) and an alert when asked", () => {
    if (!superseded) throw new Error("fixture");
    const polite = mount(SupersededCallout, { props: { superseded } });
    expect(polite.get('[role="status"]').text()).toContain("Nothing was submitted.");
    expect(polite.find('[role="alert"]').exists()).toBe(false);
    const alert = mount(SupersededCallout, { props: { superseded, role: "alert" } });
    expect(alert.get('[role="alert"]').text()).toContain("Nothing was submitted.");
  });
});

describe("the callout re-mounts as an alert (ux on #656)", () => {
  it("superseded first, then the person's refusal: a fresh element with role=alert", async () => {
    if (!superseded) throw new Error("fixture");
    const role = ref<"alert" | undefined>(undefined);
    // As PlanScreen renders it: keyed on the role.
    const Host = defineComponent(
      () => () =>
        h(SupersededCallout, { key: role.value ?? "polite", superseded, role: role.value }),
    );
    const w = mount(Host, { attachTo: document.body });
    const before = w.get('[role="status"]').element;
    role.value = "alert";
    await nextTick();
    const after = w.get('[role="alert"]').element;
    // A new live region, so a screen reader announces it (a flipped attribute isn't).
    expect(after).not.toBe(before);
    expect(before.isConnected).toBe(false);
    w.unmount();
  });
});

describe("useSupersededRole (#654)", () => {
  it("arms on the person's refused Submit, for that plan and day only, and never sticks", async () => {
    const key = ref<string | null>("2026-11-21:plan-1");
    const scope = effectScope();
    const r = scope.run(() => useSupersededRole(() => key.value));
    if (!r) throw new Error("scope");
    // Found superseded on load or by a refetch: polite.
    expect(r.role.value).toBeUndefined();
    // The person's own Submit was refused as superseded: an alert.
    r.mark();
    expect(r.role.value).toBe("alert");
    // Another plan or day disarms it, and coming back doesn't re-arm it.
    key.value = "2026-11-22:plan-2";
    await nextTick();
    expect(r.role.value).toBeUndefined();
    key.value = "2026-11-21:plan-1";
    await nextTick();
    expect(r.role.value).toBeUndefined();
    scope.stop();
  });
});
