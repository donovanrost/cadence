import RoutingDirectory from "./RoutingDirectory.vue";
import RoutingDetail from "./RoutingDetail.vue";
import { readDirectory, readDetail } from "./read-validation";
import type { ReadContext } from "../../shared/read-contracts";

export const readSurfaces = {
  routing: {
    // oxlint-disable-next-line typescript/no-unsafe-assignment -- vue-tsc checks the SFC constructor at this registration or render boundary.
    component: RoutingDirectory,
    admit: (payload: unknown, context: ReadContext) => ({
      page: readDirectory(payload, context),
      context,
    }),
  },
  routing_detail: {
    // oxlint-disable-next-line typescript/no-unsafe-assignment -- vue-tsc checks the SFC constructor at this registration or render boundary.
    component: RoutingDetail,
    admit: (payload: unknown, context: ReadContext) => ({
      page: readDetail(payload, context),
      context,
    }),
  },
} as const;
