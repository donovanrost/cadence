defmodule Cadence.Dashboards.Sources.EventsWorkflowJobScopeTest do
  @moduledoc "The events frame's workflow job comes only from the event's own mission."
  use Cadence.DataCase, async: false

  alias Cadence.Dashboards.Sources.Events.Presentation
  alias Cadence.Jobs
  alias Cadence.Telemetry.Storage.BackfillLifecycleEvent

  test "a lifecycle event naming another mission's run shows no job" do
    assert {:ok, _job} =
             Repo.transaction(fn ->
               {:ok, job} =
                 Jobs.enqueue_in_transaction(
                   :telemetry_historical_data_workflow,
                   "mission-owner",
                   "run-shared-id",
                   %{}
                 )

               job
             end)

    own = %BackfillLifecycleEvent{mission_id: "mission-owner", backfill_run_id: "run-shared-id"}
    other = %BackfillLifecycleEvent{own | mission_id: "mission-other"}

    assert %Jobs.Job{mission_id: "mission-owner"} =
             Presentation.default_telemetry_backfill_workflow_job(own)

    assert Presentation.default_telemetry_backfill_workflow_job(other) == nil
    assert Presentation.default_telemetry_backfill_workflow_job(%{own | mission_id: nil}) == nil
  end
end
