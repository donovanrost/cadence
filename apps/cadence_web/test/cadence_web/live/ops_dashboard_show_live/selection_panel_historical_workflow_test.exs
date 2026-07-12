defmodule CadenceWeb.OpsDashboardShowLive.SelectionPanelHistoricalWorkflowTest do
  use Cadence.DataCase, async: false

  import Phoenix.Component, only: [assign: 3]

  alias Cadence.Dashboards.DataLink
  alias CadenceWeb.OpsDashboardShowLive.SelectionPanel
  alias Phoenix.LiveView.Socket

  test "put_historical_workflow_link_selection clears stale outcomes by default" do
    link = direct_backfill_event_link()

    socket =
      socket(%{
        current_scope: %{organization_id: "org-1"},
        current_mission: %{mission_id: "mission-1"},
        data_link_action_outcome: %{action: :retry_job}
      })

    socket =
      SelectionPanel.put_historical_workflow_link_selection(
        socket,
        %{
          "selected_target" => "telemetry_backfill_lifecycle_event",
          "selected_id" => "backfill-event-1"
        },
        link,
        patch: fn socket, query -> assign(socket, :patched_query, query) end
      )

    assert {:data_link, inspector} = socket.assigns.panel
    assert inspector.target == :telemetry_backfill_lifecycle_event
    assert socket.assigns.data_link_action_outcome == nil
  end

  test "put_historical_workflow_link_selection preserves outcomes for action result selections" do
    link = direct_backfill_event_link()
    outcome = %{action: :retry_job, target_event_id: "backfill-event-1"}

    socket =
      socket(%{
        current_scope: %{organization_id: "org-1"},
        current_mission: %{mission_id: "mission-1"},
        data_link_action_outcome: outcome
      })

    socket =
      SelectionPanel.put_historical_workflow_link_selection(
        socket,
        %{
          "selected_target" => "telemetry_backfill_lifecycle_event",
          "selected_id" => "backfill-event-1"
        },
        link,
        preserve_data_link_action_outcome?: true,
        patch: fn socket, query -> assign(socket, :patched_query, query) end
      )

    assert {:data_link, inspector} = socket.assigns.panel
    assert inspector.target == :telemetry_backfill_lifecycle_event
    assert socket.assigns.data_link_action_outcome == outcome

    assert socket.assigns.data_link_action_outcome_query == %{
             "selected_target" => "telemetry_backfill_lifecycle_event",
             "selected_id" => "backfill-event-1"
           }
  end

  defp socket(assigns) do
    %Socket{
      assigns:
        Map.merge(
          %{
            __changed__: %{},
            panel: nil,
            dashboard_selected_data_ref: nil,
            dashboard_selection_query: nil,
            dashboard_selection_state: "none",
            dashboard_evidence_query: nil,
            dashboard_engine_result: nil,
            dashboard_engine_frames_by_placement: nil,
            dashboard_data_realms: [],
            dashboard_data_bindings: [],
            dashboard_document: nil,
            current_scope: %{organization_id: "org-1"},
            current_mission: %{mission_id: "mission-1"},
            context_scope_kind: nil,
            context_scope_id: nil,
            context_spacecraft_id: nil,
            dashboard_scope_context: %{},
            dashboard_time_mode: "live",
            dashboard_time_from: nil,
            dashboard_time_to: nil,
            dashboard_replay_run_id: nil,
            dashboard_time_context: %{},
            dashboard_data_realm: nil,
            dashboard_data_view: nil,
            dashboard_compare_data_view: nil,
            dashboard_data_source_id: nil,
            dashboard_source_binding_id: nil,
            dashboard_data_context: %{},
            dashboard_limit_mode: nil,
            dashboard_limit_context: %{},
            data_link_action_outcome: nil,
            data_link_action_outcome_query: nil
          },
          assigns
        )
    }
  end

  defp direct_backfill_event_link do
    %DataLink{
      link_id: "direct:telemetry_backfill_lifecycle_event:backfill-event-1",
      label: "Backfill lifecycle event",
      target: :telemetry_backfill_lifecycle_event,
      target_id: "backfill-event-1",
      source: :annotation,
      context: %{data: %{realm: "flight"}}
    }
  end
end
