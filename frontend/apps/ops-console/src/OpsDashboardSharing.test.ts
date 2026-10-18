import { expect, test } from "vite-plus/test";
import { SharedViewLegacyRedirect } from "@cadence/dashboards-and-exploration/sharing";
import OpsDashboardShare from "./OpsDashboardShare.vue";
import OpsDashboardSnapshot from "./OpsDashboardSnapshot.vue";
import { OPS_COMPONENTS } from "./ops-components";
test("legacy sharing entries delegate to the canonical host link without duplicate viewers", () => {
  expect(OpsDashboardShare).toBe(SharedViewLegacyRedirect);
  expect(OpsDashboardSnapshot).toBe(SharedViewLegacyRedirect);
  expect(OPS_COMPONENTS.OpsDashboardShare).toBe(SharedViewLegacyRedirect);
  expect(OPS_COMPONENTS.OpsDashboardSnapshot).toBe(SharedViewLegacyRedirect);
});
