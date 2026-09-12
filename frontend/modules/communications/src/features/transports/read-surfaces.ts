import TransportDirectory from "./TransportDirectory.vue";
import TransportDetail from "./TransportDetail.vue";
import { readDirectory, readDetail } from "./read-validation";
import type { ReadContext } from "../../shared/read-contracts";

export const readSurfaces = {
  transports: {
    component: TransportDirectory,
    admit: (payload: unknown, context: ReadContext) => ({ page: readDirectory(payload, context) }),
  },
  transport: {
    component: TransportDetail,
    admit: (payload: unknown, context: ReadContext) => ({ page: readDetail(payload, context) }),
  },
} as const;
