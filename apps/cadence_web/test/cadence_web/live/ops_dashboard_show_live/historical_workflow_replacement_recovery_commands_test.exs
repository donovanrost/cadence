defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowReplacementRecoveryCommandsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [assign: 3]

  alias CadenceWeb.OpsDashboardShowLive.{
    HistoricalWorkflow,
    HistoricalWorkflowActionOutcome,
    HistoricalWorkflowPresenter
  }

  alias CadenceWeb.OpsDashboardShowLive.SelectionQuery
  alias Phoenix.LiveView.Socket

  test "inspecting stale replacement jobs records and selects audit event" do
    event = workflow_event("event-stale-inspection-1")

    socket =
      HistoricalWorkflow.inspect_stale_replacement_job(
        socket(%{panel: dashboard_context_panel()}),
        "job-stale-1",
        "event-source-1",
        Keyword.merge(selection_opts(),
          replacement_run_id: "run-stale-replacement",
          inspect_stale_replacement_job: fn job_id, event_id, _scope, _mission ->
            assert job_id == "job-stale-1"
            assert event_id == "event-source-1"
            {:ok, event}
          end
        )
      )

    assert socket.assigns.flash["info"] == "Recorded stale replacement job inspection."

    assert_action_outcome(socket, %{
      action: "stale_replacement_job_inspection",
      status: "ok",
      kind: "info",
      reason: "stale_replacement_job_inspection_recorded",
      target_event_id: "event-stale-inspection-1",
      target_run_id: "run-stale-replacement",
      result_event_ids: "event-stale-inspection-1",
      dashboard_context: dashboard_context_attrs(),
      message: "Recorded stale replacement job inspection."
    })

    assert SelectionQuery.value(socket.assigns.selected_workflow_query, "selected_id") ==
             "event-stale-inspection-1"

    assert socket.assigns.selected_workflow_link.target_id == "event-stale-inspection-1"
  end

  test "inspecting stale replacement jobs preserves replacement run scope on errors" do
    socket =
      HistoricalWorkflow.inspect_stale_replacement_job(
        socket(),
        "job-stale-1",
        "event-source-1",
        replacement_run_id: "run-stale-replacement",
        inspect_stale_replacement_job: fn job_id, event_id, _scope, _mission ->
          assert job_id == "job-stale-1"
          assert event_id == "event-source-1"

          {:error,
           {:historical_workflow_stale_replacement_inspection_blocked, event_id, :job_not_stale}}
        end
      )

    assert socket.assigns.flash["error"] ==
             "Stale replacement job action was blocked for event event-source-1: the selected replacement job is not stale."

    assert_action_outcome(socket, %{
      action: "stale_replacement_job_inspection",
      status: "error",
      kind: "error",
      reason: "stale_replacement_job_inspection_failed",
      target_event_id: "event-source-1",
      target_run_id: "run-stale-replacement",
      message:
        "Stale replacement job action was blocked for event event-source-1: the selected replacement job is not stale."
    })
  end

  test "inspecting missing replacement jobs records and selects audit event" do
    event =
      "event-missing-inspection-1"
      |> workflow_event()
      |> Map.put(:backfill_run_id, "run-missing-replacement")

    socket =
      HistoricalWorkflow.inspect_missing_replacement_job(
        socket(%{panel: dashboard_context_panel()}),
        "group-1",
        "run-missing-replacement",
        Keyword.merge(selection_opts(),
          inspect_missing_replacement_job: fn request_group_id,
                                              replacement_run_id,
                                              _scope,
                                              _mission ->
            assert request_group_id == "group-1"
            assert replacement_run_id == "run-missing-replacement"
            {:ok, event}
          end
        )
      )

    assert socket.assigns.flash["info"] == "Recorded missing replacement job inspection."

    assert_action_outcome(socket, %{
      action: "missing_replacement_job_inspection",
      status: "ok",
      kind: "info",
      reason: "missing_replacement_job_inspection_recorded",
      target_event_id: "event-missing-inspection-1",
      target_run_id: "run-missing-replacement",
      request_group_id: "group-1",
      result_event_ids: "event-missing-inspection-1",
      dashboard_context: dashboard_context_attrs(),
      message: "Recorded missing replacement job inspection."
    })

    assert SelectionQuery.value(socket.assigns.selected_workflow_query, "selected_id") ==
             "event-missing-inspection-1"

    assert socket.assigns.selected_workflow_link.target_id == "event-missing-inspection-1"
  end

  test "inspecting missing replacement jobs preserves request group context on errors" do
    socket =
      HistoricalWorkflow.inspect_missing_replacement_job(
        socket(),
        "group-1",
        "run-missing-replacement",
        inspect_missing_replacement_job: fn request_group_id,
                                            replacement_run_id,
                                            _scope,
                                            _mission ->
          assert request_group_id == "group-1"
          assert replacement_run_id == "run-missing-replacement"

          {:error,
           {:historical_workflow_missing_replacement_inspection_blocked, replacement_run_id,
            :replacement_event_not_found}}
        end
      )

    assert socket.assigns.flash["error"] ==
             "Missing replacement job inspection was blocked for run run-missing-replacement: replacement event not found."

    assert_action_outcome(socket, %{
      action: "missing_replacement_job_inspection",
      status: "error",
      kind: "error",
      reason: "missing_replacement_job_inspection_failed",
      target_run_id: "run-missing-replacement",
      request_group_id: "group-1",
      message:
        "Missing replacement job inspection was blocked for run run-missing-replacement: replacement event not found."
    })
  end

  test "requeueing stale replacement jobs records and selects audit event" do
    event =
      "event-stale-requeue-1"
      |> workflow_event()
      |> Map.put(:backfill_run_id, "run-stale-requeued")

    socket =
      HistoricalWorkflow.requeue_stale_replacement_job(
        socket(%{panel: dashboard_context_panel()}),
        "job-stale-1",
        "event-source-1",
        Keyword.merge(selection_opts(),
          replacement_run_id: "run-stale-replacement",
          requeue_stale_replacement_job: fn job_id, event_id, _scope, _mission ->
            assert job_id == "job-stale-1"
            assert event_id == "event-source-1"
            {:ok, %{job_id: "job-stale-1", status: :queued}, event}
          end
        )
      )

    assert socket.assigns.flash["info"] ==
             "Requeued stale replacement job job-stale-1 and recorded audit event."

    assert_action_outcome(socket, %{
      action: "stale_replacement_job_requeue",
      status: "ok",
      kind: "info",
      reason: "stale_replacement_job_requeue_recorded",
      job_id: "job-stale-1",
      target_event_id: "event-stale-requeue-1",
      target_run_id: "run-stale-replacement",
      result_event_ids: "event-stale-requeue-1",
      dashboard_context: dashboard_context_attrs(),
      message: "Requeued stale replacement job job-stale-1 and recorded audit event."
    })

    assert SelectionQuery.value(socket.assigns.selected_workflow_query, "selected_id") ==
             "event-stale-requeue-1"

    assert socket.assigns.selected_workflow_link.target_id == "event-stale-requeue-1"
  end

  defp selection_opts do
    [
      put_link_selection: fn socket, query, link ->
        socket
        |> assign(:selected_workflow_query, query)
        |> assign(:selected_workflow_link, link)
      end
    ]
  end

  defp socket(assigns \\ %{}) do
    %Socket{
      assigns:
        Map.merge(
          %{
            __changed__: %{},
            flash: %{},
            current_scope: %{organization_id: "org-1", user: %{id: "operator-1"}},
            current_mission: %{mission_id: "mission-1"},
            panel: nil,
            selected_point_id: nil,
            dashboard_selected_data_ref: nil,
            dashboard_data_realm: "backfill",
            dashboard_data_source_id: nil,
            dashboard_source_binding_id: nil,
            dashboard_time_from: nil,
            dashboard_time_to: nil
          },
          assigns
        )
    }
  end

  defp workflow_event(event_id) do
    %{
      backfill_lifecycle_event_id: event_id,
      realm: "backfill",
      data_source_id: "managed_questdb_backfill",
      binding_id: "binding-alpha",
      point_id: "HK.counter"
    }
  end

  defp dashboard_context_panel do
    {:data_link,
     %{
       rows: [
         %{label: "Dashboard context", value: "dashboard-recovery"},
         %{label: "Dashboard context version", value: "3"},
         %{label: "Dashboard context time mode", value: "archive"},
         %{label: "Dashboard context data view", value: "as_recorded"},
         %{label: "Dashboard context limit mode", value: "observed"}
       ]
     }}
  end

  defp dashboard_context_attrs do
    %{
      dashboard_id: "dashboard-recovery",
      dashboard_version: "3",
      dashboard_time_mode: "archive",
      dashboard_data_view: "as_recorded",
      dashboard_limit_mode: "observed"
    }
  end

  defp assert_action_outcome(socket, expected_attrs) do
    assert %HistoricalWorkflowActionOutcome{} =
             outcome =
             socket.assigns.data_link_action_outcome

    assert HistoricalWorkflowPresenter.action_attrs(outcome) == expected_attrs
  end
end
