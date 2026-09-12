import { mount } from "@vue/test-utils";
import { expect, test } from "vite-plus/test";
import { OpsDataSources } from "../../data-sources";
import ReaderEntry from "../../../../../apps/ops-console/src/OpsDataSources.vue";
import RegistrationEntry from "../../../../../apps/ops-console/src/OpsDataSourceRegistration.vue";
import SettingsEntry from "../../../../../apps/ops-console/src/OpsDataSourceSettings.vue";
import type { Page } from "./presentation-contract";
// The four SFC entry constructors are checked by vue-tsc.
/* oxlint-disable typescript/no-unsafe-assignment */
const entries = {
  owner: OpsDataSources,
  reader: ReaderEntry,
  registration: RegistrationEntry,
  settings: SettingsEntry,
};
/* oxlint-enable typescript/no-unsafe-assignment */
for (const [name, component] of Object.entries(entries)) {
  test(name + " compatibility entry links to the exact canonical source workspace", () => {
    for (const [mode, source, suffix] of [
      ["reader", null, ""],
      ["reader", "source/a", "/source%2Fa"],
      ["registration", null, "/registration/new"],
      ["settings", "source/a", "/source%2Fa/settings"],
    ] as const) {
      const w = mount(component, {
        props: { page: { mission_id: "mission", mode, data_source_id: source } satisfies Page },
      });
      expect(w.get("#sources-open-workspace").attributes("href")).toBe(
        "/missions/mission/ops/data-sources" + suffix,
      );
      expect(w.find("form").exists()).toBe(false);
      w.unmount();
    }
  });
}
test("compatibility entry contains unavailable or malformed subjects", () => {
  for (const page of [
    { mission_id: "", mode: "reader", data_source_id: null },
    { mission_id: "mission", mode: "settings", data_source_id: null },
    { mission_id: "mission", mode: "registration", data_source_id: "unexpected" },
  ] satisfies Page[]) {
    const w = mount(OpsDataSources, { props: { page } });
    expect(w.find("#sources-open-workspace").exists()).toBe(false);
    w.unmount();
  }
});
