import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it } from "vite-plus/test";
import { defineComponent, h, ref } from "vue";
import ApButton from "./ApButton.vue";
import ApInlineConfirm from "./ApInlineConfirm.vue";

/**
 * A caller as screens use it: a trigger, the sentence, optional fields; it closes on success. Each
 * host owns its `open` ref, so a test can close it as a screen would (no casts into the vm).
 */
function makeHost() {
  const open = ref(false);
  const Host = defineComponent({
    props: {
      withReason: { type: Boolean, default: false },
      refusal: { type: String, default: null },
      keepTrigger: { type: Boolean, default: true },
    },
    emits: ["confirm", "cancel"],
    setup(props, { emit }) {
      return () =>
        h("main", [
          h("h1", "Provider account"),
          h(
            ApInlineConfirm,
            {
              open: open.value,
              "onUpdate:open": (v: boolean) => (open.value = v),
              action: "Remove account",
              busyReason: "Removing…",
              refusal: props.refusal,
              onConfirm: () => emit("confirm"),
              onCancel: () => emit("cancel"),
            },
            {
              trigger: ({ attrs }: { attrs: Record<string, unknown> }) =>
                props.keepTrigger
                  ? h(ApButton, { variant: "danger", ...attrs }, () => "Remove account…")
                  : null,
              default: () => "Remove Svalbard? Missions can't book with it afterwards.",
              ...(props.withReason
                ? { fields: () => h("textarea", { "aria-label": "Reason" }) }
                : {}),
            },
          ),
        ]);
    },
  });
  return { Host, open };
}
let current = makeHost();
let wrapper: ReturnType<typeof mount> | null = null;
const host = (props: Record<string, unknown> = {}) => {
  current = makeHost();
  wrapper = mount(current.Host, { props, attachTo: document.body });
  return wrapper;
};
afterEach(() => {
  wrapper?.unmount();
  wrapper = null;
});
const active = () => document.activeElement;
const trigger = (w: ReturnType<typeof host>) => w.get("button[aria-controls]");

describe("ApInlineConfirm (design-language §7)", () => {
  it("wires the trigger and opens on Cancel, never the action, with Cancel first (A1)", async () => {
    const w = host();
    expect(trigger(w).attributes("aria-expanded")).toBe("false");
    await trigger(w).trigger("click");
    await flushPromises();
    expect(trigger(w).attributes("aria-expanded")).toBe("true");
    const group = w.get('[role="group"]');
    expect(trigger(w).attributes("aria-controls")).toBe(group.attributes("id"));
    const buttons = group.findAll("button").map((b) => b.text());
    expect(buttons).toEqual(["Cancel", "Remove account"]);
    expect(active()?.textContent?.trim()).toBe("Cancel");
    expect(group.classes()).toContain("bg-raised");
  });
  it("opens on its reason field when it has one", async () => {
    const w = host({ withReason: true });
    await trigger(w).trigger("click");
    await flushPromises();
    expect(active()?.getAttribute("aria-label")).toBe("Reason");
  });
  it("backs out on Esc and on Cancel, returning focus to the trigger (A4, A5)", async () => {
    const w = host();
    await trigger(w).trigger("click");
    await flushPromises();
    await w.get('[role="group"]').trigger("keydown", { key: "Escape" });
    await flushPromises();
    expect(w.find('[role="group"]').exists()).toBe(false);
    expect(active()).toBe(trigger(w).element);
    expect(w.emitted("cancel")).toHaveLength(1);
    await trigger(w).trigger("click");
    await flushPromises();
    await w.findAll('[role="group"] button')[0]?.trigger("click");
    await flushPromises();
    expect(active()).toBe(trigger(w).element);
  });
  it("emits the action; when the caller closes it and the trigger is gone, focus goes to the h1", async () => {
    const w = host();
    await trigger(w).trigger("click");
    await flushPromises();
    await w.findAll('[role="group"] button')[1]?.trigger("click");
    expect(w.emitted("confirm")).toHaveLength(1);
    await w.setProps({ keepTrigger: false });
    current.open.value = false;
    await flushPromises();
    expect(active()?.tagName).toBe("H1");
  });
  it("announces a refusal as an alert under the sentence, keeping focus and staying open (#463)", async () => {
    const w = host();
    await trigger(w).trigger("click");
    await flushPromises();
    const live = () => w.get('[role="alert"]');
    expect(live().attributes("aria-live")).toBeUndefined();
    expect(live().text()).toBe("");
    await w.setProps({ refusal: "The provider refused: missions still book with it." });
    expect(live().text()).toBe("The provider refused: missions still book with it.");
    expect(w.find('[role="group"]').exists()).toBe(true);
    expect(active()?.textContent?.trim()).toBe("Cancel");
  });
  it("opens through v-model too, returning focus to what was focused (a ⋯ menu's trigger)", async () => {
    const w = host({ keepTrigger: false });
    const menu = document.createElement("button");
    menu.textContent = "⋯";
    document.querySelector("main")?.append(menu);
    menu.focus();
    current.open.value = true;
    await flushPromises();
    expect(active()?.textContent?.trim()).toBe("Cancel");
    await w.get('[role="group"]').trigger("keydown", { key: "Escape" });
    await flushPromises();
    expect(active()).toBe(menu);
  });
  it("keeps one open at a time: opening another cancels the first without stealing focus back", async () => {
    const a = mount(makeHost().Host, { attachTo: document.body });
    const b = mount(makeHost().Host, { attachTo: document.body });
    await a.get("button[aria-controls]").trigger("click");
    await flushPromises();
    await b.get("button[aria-controls]").trigger("click");
    await flushPromises();
    expect(a.find('[role="group"]').exists()).toBe(false);
    expect(a.emitted("cancel")).toHaveLength(1);
    expect(b.find('[role="group"]').exists()).toBe(true);
    expect(active()?.textContent?.trim()).toBe("Cancel");
    expect(b.get('[role="group"]').element.contains(active())).toBe(true);
    // The first's trigger doesn't take focus back when the second closes it (lead).
    expect(active()).not.toBe(a.get("button[aria-controls]").element);
    a.unmount();
    b.unmount();
  });
});
