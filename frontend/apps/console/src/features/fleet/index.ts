/**
 * Public API of the fleet feature (approved by lead). Other features import fleet data and the
 * matrix only from here.
 */
export {
  fetchFleet,
  fleetStates,
  type Fleet,
  type FleetSpacecraft,
  type FleetState,
  type FleetWorstPoint,
} from "./api.ts";
export {
  FLEET_POLL_OFFLINE_S,
  FLEET_REFETCH_GAP_MS,
  throttle,
  useFleet,
  type FleetHandle,
} from "./useFleet.ts";
export {
  fleetOpState,
  fleetStateWord,
  layoutMatrix,
  matrixNaturalHeight,
  type MatrixLayout,
} from "./matrix.ts";
export { default as FleetMatrix } from "./FleetMatrix.vue";
/** Typed test builders for fleet snapshots (used by other features' tests). */
export { fleetOf, spacecraftRow } from "./fixtures.ts";
