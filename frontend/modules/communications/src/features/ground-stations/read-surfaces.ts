import GroundStationDirectory from "./GroundStationDirectory.vue";
import GroundStationDetail from "./GroundStationDetail.vue";
import { readDirectory, readDetail } from "./read-validation";
import type { ReadContext } from "../../shared/read-contracts";

export const readSurfaces = {
  ground_stations: {
    component: GroundStationDirectory,
    admit: (payload: unknown, context: ReadContext) => ({ page: readDirectory(payload, context) }),
  },
  ground_station: {
    component: GroundStationDetail,
    admit: (payload: unknown, context: ReadContext) => ({ page: readDetail(payload, context) }),
  },
} as const;
