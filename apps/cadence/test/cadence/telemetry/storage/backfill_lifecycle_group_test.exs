defmodule Cadence.Telemetry.Storage.BackfillLifecycleGroupTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Telemetry.Storage.BackfillLifecycleEvent
  alias Cadence.Telemetry.Storage.BackfillLifecycleGroup

  test "computes action eligibility from latest effective item stages" do
    requested_events = [
      event("request-1", "run-1", "requested", 1),
      event("request-2", "run-2", "requested", 2),
      event("request-3", "run-3", "requested", 3)
    ]

    assert BackfillLifecycleGroup.action_eligibility(requested_events) == %{
             request: 0,
             approve: 3,
             reject: 3,
             start: 0,
             complete: 0,
             fail: 0
           }

    approved_events =
      requested_events ++
        [
          event("approved-1", "run-1", "approved", 1),
          event("approved-2", "run-2", "approved", 2),
          event("approved-3", "run-3", "approved", 3)
        ]

    assert BackfillLifecycleGroup.action_eligibility(approved_events) == %{
             request: 0,
             approve: 0,
             reject: 3,
             start: 3,
             complete: 0,
             fail: 0
           }

    started_events =
      approved_events ++
        [
          event("started-1", "run-1", "started", 1),
          event("started-2", "run-2", "started", 2),
          event("started-3", "run-3", "started", 3)
        ]

    assert BackfillLifecycleGroup.action_eligibility(started_events) == %{
             request: 0,
             approve: 0,
             reject: 0,
             start: 0,
             complete: 3,
             fail: 3
           }
  end

  test "returns explicit transition candidates or domain rejection" do
    events = [
      event("request-1", "run-1", "requested", 1),
      event("request-2", "run-2", "requested", 2)
    ]

    assert {:ok, candidates} = BackfillLifecycleGroup.transition_candidates(events, "approved")
    assert Enum.map(candidates, & &1.backfill_run_id) == ["run-1", "run-2"]

    assert BackfillLifecycleGroup.transition_candidates(events, "started") ==
             {:error, {:no_eligible_items, "started"}}

    approved_events =
      events ++
        [
          event("approved-1", "run-1", "approved", 1),
          event("approved-2", "run-2", "approved", 2)
        ]

    assert BackfillLifecycleGroup.transition_candidates(approved_events, "approved") ==
             {:error, {:no_eligible_items, "approved"}}

    assert BackfillLifecycleGroup.transition_candidates(events, nil) ==
             {:error, {:no_eligible_items, nil}}
  end

  test "corrected request replaces the original item for group stage candidates" do
    events = [
      event("request-1", "run-1", "requested", 1),
      event("request-2", "run-2", "requested", 2),
      event("request-3", "run-3", "requested", 3),
      event("failed-3", "run-3", "failed", 3),
      event("correction-request-3", "run-3-corrected", "requested", 3,
        corrects_event_id: "failed-3",
        corrects_run_id: "run-3"
      )
    ]

    assert events
           |> BackfillLifecycleGroup.stage_candidates("approved")
           |> Enum.map(& &1.backfill_run_id) == ["run-1", "run-2", "run-3-corrected"]

    refute Enum.any?(
             BackfillLifecycleGroup.effective_events(events),
             &(&1.backfill_run_id == "run-3")
           )
  end

  test "transition sources use the latest eligible event for corrected items" do
    events = [
      event("request-1", "run-1", "requested", 1),
      event("approved-1", "run-1", "approved", 1),
      event("request-2", "run-2", "requested", 2),
      event("failed-2", "run-2", "failed", 2),
      event("correction-request-2", "run-2-corrected", "requested", 2,
        corrects_event_id: "failed-2",
        corrects_run_id: "run-2"
      ),
      event("correction-approved-2", "run-2-corrected", "approved", 2,
        corrects_event_id: "failed-2",
        corrects_run_id: "run-2"
      )
    ]

    assert events
           |> BackfillLifecycleGroup.stage_candidates("started")
           |> Enum.map(& &1.backfill_lifecycle_event_id) == ["request-1", "correction-request-2"]

    assert events
           |> BackfillLifecycleGroup.stage_sources("started")
           |> Enum.map(& &1.backfill_lifecycle_event_id) == [
             "approved-1",
             "correction-approved-2"
           ]

    assert {:ok, sources} = BackfillLifecycleGroup.transition_sources(events, "started")

    assert Enum.map(sources, & &1.backfill_lifecycle_event_id) == [
             "approved-1",
             "correction-approved-2"
           ]
  end

  test "summarizes active, resolved, retryable, and correction failure state" do
    group_events = [
      event("request-1", "run-1", "requested", 1, point_id: "HK.one"),
      event("request-2", "run-2", "requested", 2, point_id: "HK.two"),
      event("request-3", "run-3", "requested", 3, point_id: "HK.three"),
      event("request-4", "run-4", "requested", 4,
        point_id: "HK four amps",
        item_count: 4
      ),
      event("completed-1", "run-1", "completed", 1, point_id: "HK.one"),
      event("failed-2", "run-2", "failed", 2, point_id: "HK.two"),
      event("failed-3", "run-3", "failed", 3,
        point_id: "HK.three",
        retryable: false
      ),
      event("failed-4", "run-4", "failed", 4,
        point_id: "HK four amps",
        retryable: true,
        recovery_action: "correct_workflow_request"
      ),
      event("correction-request-3", "run-3-corrected", "requested", 3,
        point_id: "HK.three",
        corrects_event_id: "failed-3",
        corrects_run_id: "run-3"
      ),
      event("correction-started-3", "run-3-corrected", "started", 3,
        point_id: "HK.three",
        corrects_event_id: "failed-3",
        corrects_run_id: "run-3"
      )
    ]

    summary =
      BackfillLifecycleGroup.summary(group_events, group_events,
        retry_ready_fun: &(&1.backfill_lifecycle_event_id == "failed-2")
      )

    assert summary.state == "failing"
    refute summary.terminal?
    assert summary.size == 4
    assert summary.progress == "1/4 completed, 2 failed, 1 resolved"
    assert summary.completed == 1
    assert summary.failed == 2
    assert summary.resolved_failed == 1
    assert summary.retry_resolved == 0
    assert summary.correction_requested == 1
    assert summary.correction_started == 1
    assert summary.correction_completed == 0
    assert summary.correction_superseded == 0
    assert summary.retryable_failed == 1
    assert summary.nonretryable_failed == 1
    assert summary.failed_items == "HK.two, HK four amps"

    assert summary.failed_item_events ==
             "label=HK.two run=run-2 event=failed-2 recovery=unknown retryable=true; " <>
               "label=HK%20four%20amps run=run-4 event=failed-4 recovery=correct_workflow_request retryable=false"
  end

  test "counts correction supersession only after the correction completes" do
    group_events = [
      event("request-1", "run-1", "requested", 1, item_count: 2),
      event("request-2", "run-2", "requested", 2, item_count: 2),
      event("failed-2", "run-2", "failed", 2,
        item_count: 2,
        retryable: false,
        recovery_action: "correct_workflow_request"
      ),
      event("correction-request-2", "run-2-corrected", "requested", 2,
        item_count: 2,
        corrects_event_id: "failed-2",
        corrects_run_id: "run-2"
      ),
      event("correction-started-2", "run-2-corrected", "started", 2,
        item_count: 2,
        corrects_event_id: "failed-2",
        corrects_run_id: "run-2"
      )
    ]

    pending_summary = BackfillLifecycleGroup.summary(group_events, group_events)

    assert pending_summary.correction_requested == 1
    assert pending_summary.correction_started == 1
    assert pending_summary.correction_completed == 0
    assert pending_summary.correction_superseded == 0

    completed_events = [
      event("correction-completed-2", "run-2-corrected", "completed", 2,
        item_count: 2,
        corrects_event_id: "failed-2",
        corrects_run_id: "run-2"
      )
      | group_events
    ]

    completed_summary = BackfillLifecycleGroup.summary(completed_events, completed_events)

    assert completed_summary.correction_requested == 1
    assert completed_summary.correction_started == 1
    assert completed_summary.correction_completed == 1
    assert completed_summary.correction_superseded == 1
  end

  test "summarizes retry resolution without marking the retried item terminal" do
    group_events = [
      event("request-1", "run-1", "requested", 1, item_count: 2),
      event("request-2", "run-2", "requested", 2, item_count: 2),
      event("completed-1", "run-1", "completed", 1, item_count: 2),
      event("failed-2", "run-2", "failed", 2, item_count: 2),
      event("retried-2", "run-2", "retried", 2,
        item_count: 2,
        retry_source_event_id: "failed-2"
      )
    ]

    summary = BackfillLifecycleGroup.summary(group_events, group_events)

    assert summary.state == "requested"
    refute summary.terminal?
    assert summary.progress == "1/2 completed, 0 failed, 1 resolved"
    assert summary.failed == 0
    assert summary.resolved_failed == 1
    assert summary.retry_resolved == 1
    assert summary.correction_requested == 0
    assert summary.failed_items == nil
    assert summary.failed_item_events == nil
  end

  defp event(event_id, run_id, stage, item_index, opts \\ []) do
    payload =
      %{
        "workflow" => "backfill",
        "stage" => stage,
        "run_id" => run_id,
        "request_group_id" => "request-group-1",
        "request_item_index" => item_index,
        "request_item_count" => Keyword.get(opts, :item_count, 3)
      }
      |> maybe_put("corrects_event_id", Keyword.get(opts, :corrects_event_id))
      |> maybe_put("corrects_run_id", Keyword.get(opts, :corrects_run_id))
      |> maybe_put("retry_source_event_id", Keyword.get(opts, :retry_source_event_id))
      |> maybe_put_failure(Keyword.get(opts, :retryable), Keyword.get(opts, :recovery_action))

    BackfillLifecycleEvent.new(%{
      backfill_lifecycle_event_id: event_id,
      backfill_run_id: run_id,
      organization_id: "org-1",
      mission_id: "mission-1",
      point_id: Keyword.get(opts, :point_id),
      event_type: :"backfill_#{stage}",
      occurred_at: ~U[2026-06-22 12:00:00Z],
      payload: payload
    })
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_failure(map, nil, nil), do: map

  defp maybe_put_failure(map, retryable, recovery_action) do
    failure =
      %{}
      |> maybe_put("retryable", retryable)
      |> maybe_put("recovery_action", recovery_action)

    Map.put(map, "source", %{"failure" => failure})
  end
end
