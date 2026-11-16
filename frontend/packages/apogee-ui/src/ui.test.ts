import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import { createMemoryHistory, createRouter } from "vue-router";
import ApBreadcrumb from "./ApBreadcrumb.vue";
import ApButton from "./ApButton.vue";
import ApCheckRows from "./ApCheckRows.vue";
import ApEventLine from "./ApEventLine.vue";
import ApField from "./ApField.vue";
import ApPageHeader from "./ApPageHeader.vue";
import ApSegmented from "./ApSegmented.vue";
import ApSelect from "./ApSelect.vue";
import ApStatTile from "./ApStatTile.vue";

describe("ApButton", () => {
  it("stays focusable when disabled, explains why, and drops clicks", async () => {
    const wrapper = mount(ApButton, {
      props: { disabled: true, disabledReason: "Needs the 3 breaking items fixed first" },
      slots: { default: "Apply" },
    });
    const button = wrapper.get("button");
    expect(button.attributes("aria-disabled")).toBe("true");
    expect(button.attributes("disabled")).toBeUndefined();
    expect(wrapper.text()).toContain("Needs the 3 breaking items fixed first");
    await button.trigger("click");
    expect(wrapper.emitted("click")).toBeUndefined();
  });
});

describe("ApSegmented", () => {
  const options = [
    { value: "a", label: "A" },
    { value: "b", label: "B" },
    { value: "c", label: "C" },
  ] as const;

  it("moves selection with arrows, Home and End", async () => {
    const wrapper = mount(ApSegmented, { props: { options, modelValue: "a", label: "Pick" } });
    const first = wrapper.findAll("button")[0];
    await first?.trigger("keydown", { key: "ArrowLeft" });
    await first?.trigger("keydown", { key: "End" });
    await first?.trigger("keydown", { key: "ArrowDown" });
    expect(wrapper.emitted("update:modelValue")).toEqual([["c"], ["c"], ["b"]]);
  });
});

describe("ApStatTile", () => {
  it("says unknown instead of inventing a number", () => {
    const wrapper = mount(ApStatTile, { props: { label: "Stale", value: null } });
    expect(wrapper.text()).toContain("unknown");
  });
});

describe("ApStatTile caption", () => {
  it("tints the caption with captionState independently of the value", () => {
    const wrapper = mount(ApStatTile, {
      props: {
        label: "Uplinks queued",
        value: 23,
        caption: "2 await your GO",
        captionState: "caution",
      },
    });
    expect(wrapper.get("span.text-caution-text").text()).toBe("2 await your GO");
    expect(wrapper.find(".shadow-\\[inset_0_2px_0_var\\(--color-caution\\)\\]").exists()).toBe(
      false,
    );
  });
});

describe("ApSelect", () => {
  it("marks a required select aria-required, and not aria-invalid until it has an error (ux a11y A6)", async () => {
    const options = [{ value: "a", label: "A" }];
    const wrapper = mount(ApSelect, {
      props: { label: "Mission", required: true, options, modelValue: "" },
    });
    const select = wrapper.get("select");
    expect(select.attributes("aria-required")).toBe("true");
    expect(select.attributes("aria-invalid")).toBeUndefined();
    await wrapper.setProps({ error: "Choose a mission." });
    expect(select.attributes("aria-invalid")).toBe("true");
  });
});

describe("ApEventLine", () => {
  it("is a plain row without `selected`, and a toggle with it (ux U71 A8)", async () => {
    const plain = mount(ApEventLine, { props: { time: "02:51:03Z", state: "caution" } });
    expect(plain.find("button").exists()).toBe(false);
    const row = mount(ApEventLine, {
      props: { time: "02:51:03Z", state: "caution", selected: false },
    });
    const button = row.get("button");
    expect(button.attributes("aria-pressed")).toBe("false");
    await button.trigger("click");
    expect(row.emitted("select")).toHaveLength(1);
    await row.setProps({ selected: true });
    expect(row.get("button").attributes("aria-pressed")).toBe("true");
    expect(row.get("li").classes().join(" ")).toContain(
      "shadow-[inset_2px_0_0_var(--color-readout)]",
    );
  });
});

describe("ApField", () => {
  it("emits the raw string even for type=number", async () => {
    const wrapper = mount(ApField, { props: { label: "Count", type: "number", modelValue: "" } });
    await wrapper.get("input").setValue("50");
    expect(wrapper.emitted("update:modelValue")).toEqual([["50"]]);
  });
  it("marks a required field aria-required, and not aria-invalid until it has an error (ux a11y A6)", async () => {
    const wrapper = mount(ApField, { props: { label: "Name", required: true, modelValue: "" } });
    const input = wrapper.get("input");
    expect(input.attributes("aria-required")).toBe("true");
    expect(input.attributes("aria-invalid")).toBeUndefined();
    await wrapper.setProps({ error: "Name is taken." });
    expect(input.attributes("aria-invalid")).toBe("true");
  });
});

describe("ApPageHeader", () => {
  it("renders the title slot inside the single h1", () => {
    const wrapper = mount(ApPageHeader, {
      props: { title: "Apply r6 · 2 changes" },
      slots: { title: 'Apply <span class="font-mono normal-case">r6</span> · 2 changes' },
    });
    expect(wrapper.findAll("h1")).toHaveLength(1);
    expect(wrapper.get("h1 span.font-mono").text()).toBe("r6");
  });
});

describe("ApStatTile link", () => {
  it("is one link to the list behind the number when `to` is set, and a plain tile otherwise", () => {
    const router = createRouter({
      history: createMemoryHistory(),
      routes: [{ path: "/alarms", name: "alarms", component: { render: () => null } }],
    });
    const linked = mount(ApStatTile, {
      props: { label: "Critical", value: 3, state: "crit", to: { name: "alarms" } },
      global: { plugins: [router] },
    });
    const link = linked.get("a");
    expect(link.attributes("href")).toBe("/alarms");
    expect(link.text()).toContain("Critical");
    expect(link.text()).toContain("3");
    expect(
      mount(ApStatTile, { props: { label: "Critical", value: 3 } })
        .find("a")
        .exists(),
    ).toBe(false);
  });
});

describe("ApStatTile unit", () => {
  it("renders the unit after the value", () => {
    const wrapper = mount(ApStatTile, { props: { label: "VBAT", value: "23.1", unit: "V" } });
    expect(wrapper.text()).toContain("23.1V");
  });
});

describe("ApCheckRows", () => {
  it("renders an action per row when the slot is used", () => {
    const wrapper = mount(ApCheckRows, {
      props: {
        rows: [
          {
            key: "a",
            label: "Limits",
            sentence: "VBAT within limits",
            state: "nominal",
            verdict: "Pass",
          },
        ],
      },
      slots: { action: '<button type="button">Review</button>' },
    });
    expect(wrapper.text()).toContain("Pass");
    expect(wrapper.get("li button").text()).toBe("Review");
  });

  it("dims an earlier check's rows: no wash, neutral marks, verdict words kept (U27)", () => {
    const rows = [
      {
        key: "c",
        label: "Conflicts",
        sentence: "1 problem",
        state: "crit" as const,
        verdict: "NO-GO",
      },
    ];
    const live = mount(ApCheckRows, { props: { rows } });
    expect(live.get("li").classes().join(" ")).toContain("wash-crit");
    expect(live.find(".ap-mark--crit").exists()).toBe(true);

    const dimmed = mount(ApCheckRows, { props: { rows, dimmed: true } });
    expect(dimmed.get("li").classes().join(" ")).not.toContain("wash");
    expect(dimmed.find(".ap-mark--crit").exists()).toBe(false);
    expect(dimmed.find(".ap-mark--off").exists()).toBe(true);
    expect(dimmed.text()).toContain("NO-GO");
  });
});

describe("ApBreadcrumb literal", () => {
  it("keeps the case of literal crumbs", () => {
    const wrapper = mount(ApBreadcrumb, {
      props: { crumbs: [{ label: "Catalog" }, { label: "demo_spacecraft.yaml", literal: true }] },
      global: { stubs: { RouterLink: true } },
    });
    expect(wrapper.findAll("li")[1]?.classes()).toContain("normal-case");
  });
});
