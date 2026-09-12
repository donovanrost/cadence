import { expect, test } from "vite-plus/test";
import { SettingsLegacyRedirect } from "@cadence/dashboards-and-exploration/settings";
import OpsDashboardSettings from "./OpsDashboardSettings.vue";
import { OPS_COMPONENTS } from "./ops-components";

test("the legacy settings surface delegates to the dashboard module without a second implementation", () => {
  expect(OpsDashboardSettings).toBe(SettingsLegacyRedirect);
  expect(OPS_COMPONENTS.OpsDashboardSettings).toBe(SettingsLegacyRedirect);
});
