import type { Snapshot } from "@cadence/plugin-sdk/admission";
import type { InjectionKey } from "vue";
export const fleetStates = [
  "queued",
  "running",
  "completed",
  "partial",
  "failed",
  "canceled",
] as const;
export type FleetState = (typeof fleetStates)[number];
export type FleetDirectory = Snapshot<{
  contract_version: 1;
  context: { organization_id: string; mission_id: string };
  query: { page: number; state: FleetState | null };
  active_policy: {
    id: string;
    version: number;
    content_sha256: string;
    max_horizon_seconds: number;
  } | null;
  runs: {
    page: number;
    more: boolean;
    entries: Array<{
      id: string;
      lifecycle_state: FleetState;
      phase:
        | "queued"
        | "materializing"
        | "searching"
        | "optimizing"
        | "materializing_plan"
        | "finished";
      trigger_kind: "manual" | "scheduled" | "repair";
      horizon_start: string;
      horizon_end: string;
      inserted_at: string;
      policy_id: string;
      policy_version: number;
      requirement_count: number;
      candidate_plan: { id: string; version: number } | null;
    }>;
  };
}>;
export interface FleetDirectoryPort {
  context: FleetDirectory["context"];
  refresh: () => Promise<unknown>;
}
export const FLEET_DIRECTORY_PORT: InjectionKey<FleetDirectoryPort> = Symbol(
  "cadence.fleet-directory-port",
);
export type OpsFleetPlanningProps = { directory: unknown; port?: FleetDirectoryPort };
export type OpsFleetPlanningEmits = Record<never, never>;
