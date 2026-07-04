defmodule CadenceWeb.OpsDashboardShowLive.InitialStateTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.Document
  alias CadenceWeb.OpsDashboardShowLive.InitialState
  alias Phoenix.HTML.Form
  alias Phoenix.LiveView.Socket

  test "assign_loaded_dashboard establishes the dashboard show default state" do
    now = ~U[2026-06-25 12:00:00Z]

    socket =
      %Socket{assigns: %{__changed__: %{}}}
      |> InitialState.assign_loaded_dashboard(resources(),
        default_live_refresh_ms: 2_000,
        runtime_context_since: now
      )

    assert socket.assigns.dashboard_document.dashboard_id == "dashboard-1"
    assert socket.assigns.dashboard_document_mode == :published
    assert socket.assigns.dashboard_render_items == []
    assert socket.assigns.page_title == "Ops Dashboard"
    assert socket.assigns.active_dashboard_id == "dashboard-1"

    assert socket.assigns.points_by_id == %{
             "HK.temp" => %{point_id: "HK.temp", stale_timeout_ms: 5_000},
             "HK.voltage" => %{point_id: "HK.voltage", stale_timeout_ms: nil}
           }

    assert socket.assigns.stale_timeouts == %{"HK.temp" => 5_000}
    assert socket.assigns.spacecraft == [%{spacecraft_id: "SC-1"}]
    assert socket.assigns.source_endpoints == [%{source_endpoint_id: "endpoint-1"}]
    assert socket.assigns.transports == [%{transport_id: "transport-1"}]
    assert socket.assigns.link_assignments == [%{link_assignment_id: "link-1"}]
    assert socket.assigns.scheduled_contacts == [%{scheduled_contact_id: "contact-scheduled-1"}]
    assert socket.assigns.realized_contacts == [%{realized_contact_id: "contact-realized-1"}]
    assert socket.assigns.context_spacecraft_id == nil
    assert socket.assigns.context_scope_kind == nil
    assert socket.assigns.context_scope_id == nil
    assert socket.assigns.context_scope_ids == []

    assert socket.assigns.dashboard_time_mode == "live"
    assert socket.assigns.dashboard_time_validation == "ok"
    assert socket.assigns.dashboard_data_realm == "flight"
    assert socket.assigns.dashboard_replay_runs == [%{replay_run_id: "replay-run-1"}]
    assert socket.assigns.dashboard_data_view == "canonical"
    assert socket.assigns.dashboard_limit_mode_fallback == nil

    assert socket.assigns.dashboard_data_context == %{
             "realm" => "flight",
             "view" => "canonical",
             "source_mode" => "primary",
             "source_contexts" => %{}
           }

    assert socket.assigns.dashboard_limit_context == %{"semantics_mode" => "observed"}
    assert socket.assigns.widget_data == %{}
    assert socket.assigns.backfills == %{}
    assert socket.assigns.tick_count == 0
    assert socket.assigns.edit_mode? == false
    assert socket.assigns.panel == nil
    assert socket.assigns.dashboard_selection_state == "none"
    assert socket.assigns.dashboard_evidence_query == nil
    assert socket.assigns.chart_epoch == 0
    assert socket.assigns.dashboard_engine_result == nil
    assert socket.assigns.dashboard_engine_frames_by_placement == %{}
    assert socket.assigns.dashboard_live_refresh_ms == 2_000
    assert socket.assigns.dashboard_tick_timer_ref == nil
    assert socket.assigns.dashboard_last_runtime_invalidation == nil
    assert socket.assigns.dashboard_runtime_context_since == now

    assert Form.input_value(socket.assigns.widget_form, :type) == "value_tile"

    assert Form.input_value(socket.assigns.historical_workflow_request_form, :workflow) ==
             "backfill"

    assert socket.assigns.dashboard_runtime_resolved? == false
    assert socket.assigns.dashboard_runtime_pending_appends == %{}
    assert socket.assigns.dashboard_runtime_pending_chart_remounts == %{}
    assert socket.assigns.dashboard_runtime_decisions == []
    assert socket.assigns.dashboard_runtime_coordinator.status == :idle
  end

  test "assign_loaded_dashboard falls back to the first available non-flight realm" do
    socket =
      %Socket{assigns: %{__changed__: %{}}}
      |> InitialState.assign_loaded_dashboard(
        resources(%{data_realms: ["rehearsal", "ait"]}),
        default_live_refresh_ms: 1_000
      )

    assert socket.assigns.dashboard_data_realm == "rehearsal"
    assert socket.assigns.dashboard_data_context["realm"] == "rehearsal"
  end

  defp resources(overrides \\ %{}) do
    Map.merge(
      %{
        document: document(),
        document_mode: :published,
        points: [
          %{point_id: "HK.temp", stale_timeout_ms: 5_000},
          %{point_id: "HK.voltage", stale_timeout_ms: nil}
        ],
        operational_observables: [%{observable_id: "bit_rate"}],
        spacecraft: [%{spacecraft_id: "SC-1"}],
        source_endpoints: [%{source_endpoint_id: "endpoint-1"}],
        transports: [%{transport_id: "transport-1"}],
        link_assignments: [%{link_assignment_id: "link-1"}],
        scheduled_contacts: [%{scheduled_contact_id: "contact-scheduled-1"}],
        realized_contacts: [%{realized_contact_id: "contact-realized-1"}],
        data_realms: ["rehearsal", "flight"],
        data_bindings: [%{binding_id: "flight-binding"}],
        replay_runs: [%{replay_run_id: "replay-run-1"}]
      },
      overrides
    )
  end

  defp document do
    %Document{
      dashboard_id: "dashboard-1",
      organization_id: "org-1",
      mission_id: "mission-1",
      name: "Ops Dashboard",
      placements: [],
      metadata: %{version: 1}
    }
  end
end
