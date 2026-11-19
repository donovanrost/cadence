import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import ApField from "./ApField.vue";
import ApTextarea from "./ApTextarea.vue";

/**
 * describedBy and readonly on the kit's two text fields (#313, fe-ops): a shared reason line
 * elsewhere describes the field after its own error and hint; read-only keeps the text and focus.
 */
describe.each([
  ["ApField", ApField, "input"],
  ["ApTextarea", ApTextarea, "textarea"],
] as const)("%s", (_name, Field, tag) => {
  it("describes the control by its error, its hint, then the outside line, in that order", () => {
    const w = mount(Field, {
      props: {
        label: "Comment",
        modelValue: "",
        error: "Too long.",
        hint: "Recorded.",
        describedBy: "why",
      },
    });
    const ids = (w.get(tag).attributes("aria-describedby") ?? "").split(" ");
    expect(ids).toHaveLength(3);
    expect(ids[0]).toMatch(/-error$/);
    expect(ids[1]).toMatch(/-hint$/);
    expect(ids[2]).toBe("why");
  });

  it("has no aria-describedby when there's nothing to point at", () => {
    const w = mount(Field, { props: { label: "Comment", modelValue: "" } });
    expect(w.get(tag).attributes("aria-describedby")).toBeUndefined();
  });

  it("read-only keeps its text and stays focusable (never disabled)", () => {
    const w = mount(Field, {
      props: { label: "Comment", modelValue: "Looks right", readonly: true },
      attachTo: document.body,
    });
    const el = w.get(tag).element as HTMLInputElement | HTMLTextAreaElement;
    expect(el.readOnly).toBe(true);
    expect(el.disabled).toBe(false);
    expect(el.value).toBe("Looks right");
    el.focus();
    expect(document.activeElement).toBe(el);
    w.unmount();
  });
});
