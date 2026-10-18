import { expectTypeOf, test } from "vite-plus/test";
import type { FleetStartCommand, FleetStartInputs } from "./OpsFleetPlanningNew.contracts";
import type {
  FleetRunCommand,
  FleetRunInputs,
  FleetRunReceipt,
  RunRepair,
  RunEvidence,
} from "./OpsFleetPlanningRun.contracts";

test("creation and repair inputs and receipts preserve action identity", () => {
  expectTypeOf<["create", FleetStartInputs["preview"]]>().not.toExtend<FleetStartCommand>();
  expectTypeOf<["repair", FleetRunInputs["continue"]]>().not.toExtend<FleetRunCommand>();
  expectTypeOf<{ available: true; reason: null }>().not.toExtend<RunRepair>();
  expectTypeOf<{
    contract_version: 1;
    organization_id: string;
    mission_id: string;
    fleetPlanningRunId: string;
    outcome: "repair_created";
    lifecycleState: "queued";
    phase: "queued";
    evidence: RunEvidence;
  }>().not.toExtend<FleetRunReceipt>();
});
