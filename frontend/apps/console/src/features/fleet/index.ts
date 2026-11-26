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
  type RawLimitState,
} from "./api.ts";
export {
  FLEET_POLL_OFFLINE_S,
  FLEET_REFETCH_GAP_MS,
  FLEET_TELEMETRY_GAP_MS,
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
export { default as FleetStatStrip } from "./FleetStatStrip.vue";
export { fleetSubset, statTiles, type StatTile } from "./stats.ts";
/** Typed test builders for fleet snapshots (used by other features' tests). */
export { fleetOf, spacecraftRow } from "./fixtures.ts";
export { default as TelemetryDegraded } from "./TelemetryDegraded.vue";
export { nextContact } from "./filters.ts";
/** The top bar's fleet posture (ux IA §Top bar), shared with the dashboard cockpit. */
export { default as FleetPosture } from "./posture/FleetPosture.vue";
export { postureChips, postureFromCounts, type PostureChip } from "./posture/posture.ts";
