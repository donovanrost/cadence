import TransportDirectory from "./TransportDirectory.vue";
import TransportDetail from "./TransportDetail.vue";
import { readDirectory, readDetail } from "./read-validation";
import type { ReadContext } from "../../shared/read-contracts";

export const readSurfaces = {
  transports: {
    // oxlint-disable-next-line typescript/no-unsafe-assignment -- vue-tsc checks the SFC constructor at this registration or render boundary.
    component: TransportDirectory,
    admit: (payload: unknown, context: ReadContext) => ({ page: readDirectory(payload, context) }),
  },
  transport: {
    // oxlint-disable-next-line typescript/no-unsafe-assignment -- vue-tsc checks the SFC constructor at this registration or render boundary.
    component: TransportDetail,
    admit: (payload: unknown, context: ReadContext) => ({ page: readDetail(payload, context) }),
  },
} as const;
