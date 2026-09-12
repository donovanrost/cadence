defmodule Cadence.Telemetry.HistoricalWorkflowGroupReadsTest do
  use Cadence.DataCase, async: false

  import Cadence.Telemetry.DataManagementFixtures

  alias Cadence.Reads.Telemetry, as: TelemetryReads
  alias Cadence.Telemetry.DataManagement
  alias Cadence.Telemetry.Storage.BackfillLifecycleEvents.EventRow

  @mission "mission-product"
  @organization "org-product"

  test "group evidence includes every item beyond the mission and group 1000-event boundaries" do
    insert_events("noise", 1_005)
    insert_events("selected", 1_007, second: 1)

    assert length(TelemetryReads.list_backfill_lifecycle_events(@mission, opts(limit: 1_000))) ==
             1_000

    assert {:ok, events} =
             TelemetryReads.fetch_backfill_lifecycle_group_events(@mission, "selected", opts())

    assert length(events) == 1_007
    assert Enum.all?(events, &(&1.payload["request_group_id"] == "selected"))
    assert events == Enum.sort_by(events, &{&1.occurred_at, &1.backfill_lifecycle_event_id})
  end

  test "directory pages whole groups and preserves deterministic ties and exact scope" do
    insert_events("older", 3)
    insert_events("a", 2, second: 1)
    insert_events("b", 1, second: 1)
    insert_events("foreign-org", 1, organization_id: "another-org")
    insert_events("foreign-mission", 1, mission_id: "another-mission")

    assert %{entries: [%{id: "a", event_count: 2}, %{id: "b", event_count: 1}], total: 3} =
             TelemetryReads.list_backfill_lifecycle_groups(@mission, opts(page_size: 2))

    assert %{entries: [%{id: "older", event_count: 3}], page: 2, total: 3} =
             TelemetryReads.list_backfill_lifecycle_groups(@mission, opts(page_size: 2, page: 2))

    assert %{entries: [], total: 3} =
             TelemetryReads.list_backfill_lifecycle_groups(@mission, opts(page: 99))

    assert %{entries: [], total: 0} = TelemetryReads.list_backfill_lifecycle_groups(@mission, [])

    assert {:error, {:request_group_not_found, "foreign-org"}} =
             TelemetryReads.fetch_backfill_lifecycle_group_events(@mission, "foreign-org", opts())

    assert {:error, {:request_group_not_found, "a"}} =
             TelemetryReads.fetch_backfill_lifecycle_group_events(@mission, "a", [])
  end

  test "wrapped and historical unwrapped payloads have the same group identity" do
    insert_events("group", 1)
    insert_events("legacy", 1)

    from(row in EventRow, where: row.backfill_run_id == "legacy-1")
    |> Repo.update_all(set: [payload: %{"request_group_id" => "group"}])

    insert_events("malformed", 1)

    from(row in EventRow, where: row.backfill_run_id == "malformed-1")
    |> Repo.update_all(set: [payload: %{"value" => %{"request_group_id" => 27}}])

    assert %{entries: [%{id: "group", event_count: 2}], total: 1} =
             TelemetryReads.list_backfill_lifecycle_groups(@mission, opts())

    assert {:ok, events} =
             TelemetryReads.fetch_backfill_lifecycle_group_events(@mission, "group", opts())

    assert length(events) == 2
  end

  test "group transitions reach selected requests after more than 1000 unrelated mission events" do
    insert_events("noise", 1_005)
    insert_events("selected", 2, second: 1)

    assert {:ok, events, [ok: nil, ok: nil]} =
             DataManagement.record_historical_data_workflow_group_transition(
               :backfill,
               :approved,
               "selected",
               actor(),
               dashboard_runtime_invalidation?: false
             )

    assert length(events) == 2
    assert Enum.all?(events, &(&1.event_type == :backfill_approved))

    assert {:ok, selected} =
             TelemetryReads.fetch_backfill_lifecycle_group_events(@mission, "selected", opts())

    assert length(selected) == 4

    assert {:ok, noise} =
             TelemetryReads.fetch_backfill_lifecycle_group_events(@mission, "noise", opts())

    assert Enum.all?(noise, &(&1.event_type == :backfill_requested))
  end

  test "group retry reaches the actual failed job beyond the mission event window" do
    insert_events("noise", 1_005)
    job = failed_historical_workflow_job("selected-run")

    assert {:ok, failed} =
             record_group_failed_event("selected-failure", "selected-run", 1,
               retryable: true,
               item_count: 1,
               request_group_id: "selected",
               job_id: job.job_id
             )

    assert {:ok, %{retried: 1, failed: 0, events: [event]}} =
             DataManagement.retry_historical_data_workflow_group_failed_jobs("selected", actor(),
               dashboard_runtime_invalidation?: false
             )

    assert event.payload["retry_source_event_id"] == failed.backfill_lifecycle_event_id
    assert event.backfill_run_id == job.run_id
    assert {:ok, current} = Cadence.Jobs.fetch_job(job.job_id)
    assert current.status == :queued
  end

  test "completed corrections beyond the mission window reject an obsolete correction request" do
    insert_events("noise", 1_005)
    job = failed_historical_workflow_job("selected-correction-run")

    assert {:ok, failed} =
             record_group_failed_event("selected-correction-failure", job.run_id, 1,
               retryable: false,
               item_count: 1,
               request_group_id: "selected",
               job_id: job.job_id,
               recovery_action: "correct_workflow_request"
             )

    attrs = %{
      organization_id: @organization,
      mission_id: @mission,
      backfill_run_id: "replacement-run",
      realm: :backfill,
      data_source_id: failed.data_source_id,
      binding_id: failed.binding_id,
      payload: %{"corrects_event_id" => failed.backfill_lifecycle_event_id}
    }

    assert {:ok, completion} =
             DataManagement.record_historical_data_workflow_event(
               :backfill,
               :completed,
               attrs,
               dashboard_runtime_invalidation?: false
             )

    assert TelemetryReads.backfill_lifecycle_event_corrected?(
             failed.backfill_lifecycle_event_id,
             opts(mission_id: @mission)
           )

    refute TelemetryReads.backfill_lifecycle_event_corrected?(
             failed.backfill_lifecycle_event_id,
             opts(mission_id: "another-mission")
           )

    refute TelemetryReads.backfill_lifecycle_event_corrected?(failed.backfill_lifecycle_event_id,
             mission_id: @mission,
             organization_id: "foreign"
           )

    refute TelemetryReads.backfill_lifecycle_event_corrected?(
             failed.backfill_lifecycle_event_id,
             []
           )

    assert {:error,
            {:historical_workflow_correction_source_superseded, "selected-correction-failure"}} =
             DataManagement.record_historical_data_workflow_correction_request(
               :backfill,
               actor(),
               %{
                 "original_event_id" => failed.backfill_lifecycle_event_id,
                 "request_group_id" => "selected"
               },
               dashboard_runtime_invalidation?: false
             )

    query =
      from(row in EventRow,
        where: row.backfill_lifecycle_event_id == ^completion.backfill_lifecycle_event_id
      )

    Repo.update_all(query,
      set: [
        payload: %{
          "corrects_event_id" => failed.backfill_lifecycle_event_id,
          "stage" => "completed"
        }
      ]
    )

    assert TelemetryReads.backfill_lifecycle_event_corrected?(
             failed.backfill_lifecycle_event_id,
             opts(mission_id: @mission)
           )

    Repo.update_all(query,
      set: [payload: %{"value" => %{"corrects_event_id" => 27, "stage" => "completed"}}]
    )

    refute TelemetryReads.backfill_lifecycle_event_corrected?("27", opts(mission_id: @mission))
  end

  defp actor,
    do: %{
      organization_id: @organization,
      mission_id: @mission,
      actor_id: "operator",
      actor_kind: "operator"
    }

  defp opts(extra \\ []), do: Keyword.merge([organization_id: @organization], extra)

  defp insert_events(group, count, options \\ []) do
    time = DateTime.add(~U[2026-09-09 00:00:00.000000Z], Keyword.get(options, :second, 0))

    rows =
      Enum.map(1..count, fn index ->
        run = "#{group}-#{index}"

        %{
          backfill_lifecycle_event_id: "event-#{run}",
          backfill_run_id: run,
          organization_id: Keyword.get(options, :organization_id, @organization),
          mission_id: Keyword.get(options, :mission_id, @mission),
          realm: "backfill",
          data_source_id: "managed_questdb_backfill",
          binding_id: "backfill_telemetry",
          point_id: "point-#{index}",
          event_type: "backfill_requested",
          authority: "advisory",
          occurred_at: time,
          inserted_at: time,
          payload: %{
            "value" => %{
              "request_group_id" => group,
              "request_item_index" => index,
              "request_item_count" => count,
              "workflow" => "backfill",
              "stage" => "requested"
            }
          }
        }
      end)

    assert {^count, nil} = Repo.insert_all(EventRow, rows)
  end
end
