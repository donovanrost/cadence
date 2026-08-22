defmodule CadenceWeb.OpsDashboardShowLive.RenderRuntimeAssignsTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.Document
  alias CadenceWeb.OpsDashboardShowLive.RenderRuntimeAssigns
  alias Phoenix.LiveView.Socket

  test "projects runtime summary context from sockets and assigns maps" do
    expected = %{
      current_scope: %{organization_id: "org-1"},
      mission: %{mission_id: "mission-1"},
      document: document()
    }

    assert RenderRuntimeAssigns.runtime_summary_context(%Socket{assigns: assigns()}) == expected
    assert RenderRuntimeAssigns.runtime_summary_context(assigns()) == expected
  end

  test "projects runtime diagnostics context" do
    assigns = assigns()
    runtime_invalidation = %{event_count: 0}
    runtime_invalidation_events = [%{boundary: :dashboard_version_changed}]

    assert RenderRuntimeAssigns.runtime_diagnostics_context(
             %Socket{assigns: assigns},
             runtime_invalidation,
             runtime_invalidation_events
           ) == %{
             engine_result: %{resolve_mode: :context_change},
             runtime_coordinator: %{status: :idle},
             decisions: [%{action: :accept_result}],
             resolved?: true,
             invalidation: runtime_invalidation,
             last_invalidation: %{boundary: :dashboard_version_changed},
             runtime_invalidation_events: runtime_invalidation_events,
             current_scope: %{organization_id: "org-1"},
             mission: %{mission_id: "mission-1"},
             document: document(),
             runtime_context: %{
               data_realm: "rehearsal",
               engine_result: %{resolve_mode: :context_change},
               time_context: %{"mode" => "archive"},
               time_mode: "archive",
               replay_run_id: "replay-1",
               context_since: ~U[2026-06-25 12:00:00Z],
               edit_mode?: true
             }
           }
  end

  defp assigns do
    %{
      current_mission: %{mission_id: "mission-1"},
      current_scope: %{organization_id: "org-1"},
      dashboard_document: document(),
      dashboard_engine_result: %{resolve_mode: :context_change},
      dashboard_runtime_coordinator: %{status: :idle},
      dashboard_runtime_decisions: [%{action: :accept_result}],
      dashboard_runtime_resolved?: true,
      dashboard_last_runtime_invalidation: %{boundary: :dashboard_version_changed},
      dashboard_time_mode: "archive",
      dashboard_time_context: %{"mode" => "archive"},
      dashboard_runtime_context_since: ~U[2026-06-25 12:00:00Z],
      dashboard_replay_run_id: "replay-1",
      dashboard_data_realm: "rehearsal",
      edit_mode?: true
    }
  end

  defp document do
    %Document{dashboard_id: "dashboard-1"}
  end
end
