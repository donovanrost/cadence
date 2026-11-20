import { mount } from "@vue/test-utils";
import { h } from "vue";
import { describe, expect, it } from "vite-plus/test";
import ApOption from "./ApOption.vue";
import ApTag from "./ApTag.vue";

/** #595b (lead): ApOption's tag slot sits inside the label, so it's part of the radio's name. */
describe("ApOption's tag slot", () => {
  it("renders the tag after the title, inside the radio's label", () => {
    const w = mount(ApOption, {
      props: { value: "cr-15", name: "rev", title: "catalog rev 15", modelValue: null },
      slots: { tag: () => [mountTag()] },
    });
    const label = w.get("label");
    expect(label.find("input[type=radio]").exists()).toBe(true);
    expect(label.text()).toMatch(/catalog rev 15\s*Waiting/i);
  });

  it("renders nothing extra without it", () => {
    const w = mount(ApOption, {
      props: { value: "cr-14", name: "rev", title: "catalog rev 14", modelValue: null },
    });
    expect(w.get("label").text().trim()).toBe("catalog rev 14");
  });
});

const mountTag = () => h(ApTag, { label: "Waiting", state: "caution" });
