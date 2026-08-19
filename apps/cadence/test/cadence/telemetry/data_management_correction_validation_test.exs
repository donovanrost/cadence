defmodule Cadence.Telemetry.DataManagementCorrectionValidationTest do
  use Cadence.UnitCase, async: true

  test "rejects a correction request without an original event before evidence lookup" do
    assert {:error, {:missing_field, :original_event_id}} =
             Cadence.record_telemetry_historical_data_workflow_correction_request(
               "backfill",
               %{
                 backfill_run_id: "backfill-run-corrected-minimal",
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 authority: :unknown,
                 reason: "operator_corrected_backfill"
               },
               %{
                 "original_run_id" => "",
                 "original_event_id" => "",
                 "original_job_id" => nil
               },
               dashboard_runtime_invalidation?: false
             )
  end
end
