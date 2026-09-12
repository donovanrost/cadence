import { afterEach, expect, test } from "vite-plus/test";
import { mount } from "@vue/test-utils";
import DiagnosticsLegacyRedirect from "./DiagnosticsLegacyRedirect.vue";

const wrappers: ReturnType<typeof mount>[] = [];
afterEach(() => wrappers.splice(0).forEach((wrapper) => wrapper.unmount()));

test("the compatibility surface links to the canonical host page without interpreting old evidence", () => {
  const wrapper = mount(DiagnosticsLegacyRedirect, {
    props: { mission_id: "mission/one", dashboard_id: "dashboard?two" },
    attrs: { diagnostic_rows: [{ secret: "not evidence" }], id: "legacy-root" },
  });
  wrappers.push(wrapper);
  expect(wrapper.get("#diagnostics-open-workspace").attributes("href")).toBe(
    "/missions/mission%2Fone/ops/dashboards/dashboard%3Ftwo/diagnostics",
  );
  expect(wrapper.find("#legacy-root").exists()).toBe(false);
  expect(wrapper.attributes()).not.toHaveProperty("diagnostic_rows");
  expect(wrapper.find("main").exists()).toBe(false);
});

test("missing, oversized or control-character identities never produce a navigation link", async () => {
  const wrapper = mount(DiagnosticsLegacyRedirect, {
    props: { mission_id: "mission", dashboard_id: "dashboard" },
  });
  wrappers.push(wrapper);
  for (const invalid of [undefined, "", "a\n", "a\u007f", "é".repeat(129)]) {
    await wrapper.setProps({ mission_id: invalid, dashboard_id: "dashboard" });
    expect(wrapper.find("#diagnostics-open-workspace").exists()).toBe(false);
    expect(wrapper.find('[role="status"]').exists()).toBe(true);
    await wrapper.setProps({ mission_id: "mission", dashboard_id: invalid });
    expect(wrapper.find("#diagnostics-open-workspace").exists()).toBe(false);
  }
});
