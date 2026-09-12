import RoutingDirectory from "./RoutingDirectory.vue";
import RoutingDetail from "./RoutingDetail.vue";
import { readDirectory, readDetail } from "./read-validation";
import type { ReadContext } from "../../shared/read-contracts";

export const readSurfaces = {
  routing: {
    component: RoutingDirectory,
    admit: (payload: unknown, context: ReadContext) => ({ page: readDirectory(payload, context) }),
  },
  routing_detail: {
    component: RoutingDetail,
    admit: (payload: unknown, context: ReadContext) => ({ page: readDetail(payload, context) }),
  },
} as const;
