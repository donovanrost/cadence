import type { InjectionKey } from "vue";
export type FleetStartWindow = {
  horizon_start: string;
  horizon_end: string;
  include_recurring: boolean;
};
export type FleetStartPolicy = {
  id: string;
  version: number;
  content_sha256: string;
  max_horizon_seconds: number;
  requirement_concurrency: number;
  provider_search_concurrency: number;
  max_contacts: number | null;
  max_estimated_cost_micros: number | null;
  currency: string | null;
};
export type FleetStartEvidence = {
  contract_version: 1;
  organization_id: string;
  mission_id: string;
  policy_id: string;
  policy_version: number;
  policy_sha256: string;
  input_sha256: string;
};
export type FleetStartModel = {
  contract_version: 1;
  context: { organization_id: string; mission_id: string };
  policy: FleetStartPolicy | null;
  defaults: FleetStartWindow;
};
export type FleetStartPage<T> = { page: number; total: number; more: boolean; entries: T[] };
export type FleetStartReview = {
  contract_version: 1;
  context: FleetStartModel["context"];
  window: FleetStartWindow;
  policy: FleetStartPolicy;
  evidence: FleetStartEvidence;
  requirements: FleetStartPage<{
    id: string;
    version: number;
    content_sha256: string;
    spacecraft_id: string;
    earliest_start: string;
    latest_end: string;
    priority: "critical" | "high" | "routine";
    success_measure: "any_contact" | "minimum_duration" | "minimum_data_volume" | "contact_count";
  }>;
  templates: FleetStartPage<{
    id: string;
    version: number;
    content_sha256: string;
    spacecraft_id: string;
    occurrence_count: number;
    maximum_occurrences: number;
    maximum_lookback_seconds: number;
  }>;
  occurrence_count: number;
  eligible_occurrence_count: number;
};
export type FleetStartReceipt = {
  contract_version: 1;
  organization_id: string;
  mission_id: string;
  fleetPlanningRunId: string;
  lifecycleState: "queued";
  phase: "queued";
  requirementCount: number;
  evidence: FleetStartEvidence;
};
export interface FleetStartPort {
  context: FleetStartModel["context"];
  refresh: () => Promise<unknown>;
  execute: (action: "preview" | "create", input: Record<string, unknown>) => Promise<unknown>;
}
export const FLEET_START_PORT: InjectionKey<FleetStartPort> = Symbol("cadence.fleet-start-port");
export type OpsFleetPlanningNewProps = { start: unknown; port?: FleetStartPort };
export type OpsFleetPlanningNewEmits = Record<never, never>;
