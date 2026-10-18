import { mount } from "@vue/test-utils";
import { expect, test } from "vite-plus/test";
import CadenceDateTimeRangeField from "./CadenceDateTimeRangeField.vue";

test("shows exact UTC times to the second for both ends", () => {
  const app = mount(CadenceDateTimeRangeField, {
    props: {
      id: "range",
      label: "Range",
      modelValue: { start: "2026-10-08T10:05:07Z", end: "2026-10-08T12:30:00Z" },
    },
  });
  const text = app.text();
  expect(text).toMatch(/10\s*:\s*05\s*:\s*07/);
  expect(text).toMatch(/12\s*:\s*30\s*:\s*00/);
  app.unmount();
});

test("an initially empty field still edits times once a range arrives", async () => {
  const app = mount(CadenceDateTimeRangeField, {
    props: { id: "range", label: "Range", modelValue: null },
  });
  await app.setProps({
    modelValue: { start: "2026-10-08T10:05:07Z", end: "2026-10-08T12:30:00Z" },
  });
  expect(app.text()).toMatch(/10\s*:\s*05\s*:\s*07/);
  app.unmount();
});
