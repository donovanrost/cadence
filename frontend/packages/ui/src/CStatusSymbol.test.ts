import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import CStatusSymbol from "./CStatusSymbol.vue";
import type { StatusSymbolRole } from "./status-symbol";

const statusShapes: Array<[StatusSymbolRole, string]> = [
  ["off", "small-circle"],
  ["standby", "ring"],
  ["normal", "large-circle"],
  ["caution", "square"],
  ["serious", "diamond"],
  ["critical", "downward-triangle"],
  ["unknown", "question-square"],
];

describe("CStatusSymbol", () => {
  it.each(statusShapes)("renders %s with its invariant geometry", (status, shape) => {
    const wrapper = mount(CStatusSymbol, {
      props: { label: `${status} status`, status },
    });

    expect(wrapper.attributes("data-status-role")).toBe(status);
    expect(wrapper.find(`[data-symbol-shape="${shape}"]`).exists()).toBe(true);
    expect(wrapper.attributes("role")).toBe("img");
    expect(wrapper.attributes("aria-label")).toBe(`${status} status`);
  });

  it("is decorative when no accessible label is supplied", () => {
    const wrapper = mount(CStatusSymbol, {
      props: { status: "normal" },
    });

    expect(wrapper.attributes("aria-hidden")).toBe("true");
    expect(wrapper.attributes("role")).toBeUndefined();
  });

  it("uses only the supported optical sizes", () => {
    const wrapper = mount(CStatusSymbol, {
      props: { size: 16, status: "standby" },
    });

    expect(wrapper.attributes("width")).toBe("16");
    expect(wrapper.attributes("height")).toBe("16");
    expect(wrapper.attributes("viewBox")).toBe("0 0 24 24");
  });
});
