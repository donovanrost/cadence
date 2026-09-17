import { mount } from "@vue/test-utils";
import { afterEach, expect, test } from "vite-plus/test";
import CadenceDateTimeField from "../CadenceDateTimeField.vue";

const unmounts: (() => void)[] = [];
afterEach(() => {
  for (const unmount of unmounts.splice(0)) unmount();
});
function field(modelValue = "") {
  const wrapper = mount(CadenceDateTimeField, {
    props: { id: "time", label: "Not before", modelValue },
  });
  unmounts.push(() => wrapper.unmount());
  return { wrapper, input: wrapper.get<HTMLInputElement>("input") };
}

test("native date and time selections become UTC timestamps, including seconds and clearing", async () => {
  const { wrapper, input } = field();
  expect(input.attributes("type")).toBe("datetime-local");
  expect(wrapper.get("label").text()).toContain("Not before (UTC)");
  await input.setValue("2027-01-15T13:45");
  expect(wrapper.emitted("update:modelValue")).toEqual([["2027-01-15T13:45:00Z"]]);
  await wrapper.setProps({ modelValue: "2027-01-15T13:45:00Z" });
  await input.setValue("2027-01-15T13:45:12.125");
  expect(wrapper.emitted("update:modelValue")?.at(-1)).toEqual(["2027-01-15T13:45:12.125Z"]);
  await wrapper.setProps({ modelValue: "2027-01-15T13:45:12.125Z" });
  await input.setValue("");
  expect(wrapper.emitted("update:modelValue")?.at(-1)).toEqual([""]);
});

test("native normalization and date edits preserve existing microseconds", async () => {
  for (const fraction of ["000001", "123456", "120001"]) {
    const { wrapper, input } = field(`2027-01-15T13:45:00.${fraction}Z`);
    await input.trigger("input");
    expect(wrapper.emitted("update:modelValue")).toBeUndefined();
    await input.setValue(`2027-01-16T13:45:00.${fraction.slice(0, 3)}`);
    expect(wrapper.emitted("update:modelValue")?.at(-1)).toEqual([
      `2027-01-16T13:45:00.${fraction}Z`,
    ]);
    await input.setValue("2027-01-16T13:45:00.5");
    expect(wrapper.emitted("update:modelValue")?.at(-1)).toEqual(["2027-01-16T13:45:00.5Z"]);
  }
});

test("incomplete native edits invalidate prepared actions without discarding the draft", async () => {
  const { wrapper, input } = field("2027-01-15T13:45:00Z");
  // Simulate a browser date segment while it is incomplete; happy-dom lacks that UI.
  Object.defineProperty(input.element.validity, "badInput", { get: () => true });
  await input.trigger("input");
  expect(wrapper.emitted("invalid")).toEqual([[]]);
  expect(wrapper.emitted("update:modelValue")).toBeUndefined();
});

test("range constraints and errors are connected to the native field", async () => {
  const { wrapper, input } = field();
  await wrapper.setProps({
    min: "2027-01-15T13:45:00Z",
    max: "2027-01-16T13:45:00Z",
    error: "Check the time window.",
  });
  expect(input.attributes("min")).toBe("2027-01-15T13:45:00");
  expect(input.attributes("max")).toBe("2027-01-16T13:45:00");
  expect(input.attributes("aria-invalid")).toBe("true");
  expect(input.attributes("aria-describedby")).toBe("time-error");
  expect(wrapper.get("#time-error").text()).toBe("Check the time window.");
});
