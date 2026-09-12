import GroundStationDirectory from "./GroundStationDirectory.vue";
import GroundStationDetail from "./GroundStationDetail.vue";
import { readDirectory, readDetail } from "./read-validation";
import type { ReadContext } from "../../shared/read-contracts";

export const readSurfaces = {
  ground_stations: {
    // oxlint-disable-next-line typescript/no-unsafe-assignment -- vue-tsc checks the SFC constructor at this registration or render boundary.
    component: GroundStationDirectory,
    admit: (payload: unknown, context: ReadContext) => ({ page: readDirectory(payload, context) }),
  },
  ground_station: {
    // oxlint-disable-next-line typescript/no-unsafe-assignment -- vue-tsc checks the SFC constructor at this registration or render boundary.
    component: GroundStationDetail,
    admit: (payload: unknown, context: ReadContext) => ({ page: readDetail(payload, context) }),
  },
} as const;
