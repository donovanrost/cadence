import CommsOverviewPage from "./CommsOverviewPage.vue";
import { readOverview } from "./read-validation";
export const readSurfaces = {
  // oxlint-disable-next-line typescript/no-unsafe-assignment -- vue-tsc checks the SFC constructor at this registration or render boundary.
  overview: { component: CommsOverviewPage, admit: readOverview },
} as const;
