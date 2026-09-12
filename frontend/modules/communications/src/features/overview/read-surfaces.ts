import CommsOverviewPage from "./CommsOverviewPage.vue";
import { readOverview } from "./read-validation";
export const readSurfaces = {
  overview: { component: CommsOverviewPage, admit: readOverview },
} as const;
