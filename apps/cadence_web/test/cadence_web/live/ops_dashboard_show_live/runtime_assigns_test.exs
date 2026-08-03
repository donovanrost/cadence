defmodule CadenceWeb.OpsDashboardShowLive.RuntimeAssignsTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.Document
  alias CadenceWeb.OpsDashboardShowLive.{RuntimeAssigns, RuntimeContext}
  alias Phoenix.LiveView.Socket

  test "projects runtime query attrs from assigns with supplied defaults" do
    attrs =
      assigns()
      |> RuntimeAssigns.runtime_query_attrs(%{
        default_realm: "flight",
        default_data_view: "canonical",
        default_source_binding_id: "flight-binding"
      })

    assert attrs == %{
             selected_ref: %{"target" => "telemetry_sample"},
             selection_query: %{"selected_id" => "sample-1"},
             evidence_query: nil,
             scope_kind: "spacecraft",
             scope_id: "sc-1",
             scope_ids: ["sc-1"],
             time_mode: "archive",
             time_axis: nil,
             time_from: "2026-01-01T00:00:00Z",
             time_to: "2026-01-01T00:05:00Z",
             replay_run_id: nil,
             realm: "rehearsal",
             default_realm: "flight",
             data_view: "as_recorded",
             default_data_view: "canonical",
             compare_data_view: "all_revisions",
             data_source_id: "questdb-rehearsal",
             source_binding_id: "rehearsal-binding",
             default_source_binding_id: "flight-binding",
             limit_mode: "observed",
             hidden_markers: nil
           }
  end

  test "builds runtime context from assigns" do
    assert %RuntimeContext{
             scope_kind: "spacecraft",
             scope_id: "sc-1",
             scope_ids: ["sc-1"],
             spacecraft_id: "sc-1",
             time_mode: "archive",
             time_context: %{"mode" => "archive"},
             realm: "rehearsal",
             compare_data_view: "all_revisions",
             data_context: %{"realm" => "rehearsal"},
             limit_context: %{"semantics_mode" => "observed"}
           } = RuntimeAssigns.runtime_context(assigns())
  end

  test "projects data-link runtime context from assigns" do
    assert RuntimeAssigns.data_link_runtime_context(assigns()) == %{
             time: %{"mode" => "archive"},
             data: %{"realm" => "rehearsal"},
             limit: %{"semantics_mode" => "observed"}
           }
  end

  test "projects runtime invalidation context from sockets and assigns maps" do
    socket = %Socket{assigns: assigns()}

    expected = %{
      data_realm: "rehearsal",
      engine_result: %{resolve_mode: :initial},
      time_context: %{"mode" => "archive"},
      time_mode: "archive",
      replay_run_id: nil,
      context_since: ~U[2026-06-25 12:00:00Z],
      edit_mode?: false
    }

    assert RuntimeAssigns.runtime_invalidation_context(socket) == expected
    assert RuntimeAssigns.runtime_invalidation_context(assigns()) == expected
  end

  test "projects engine request attrs from sockets and assigns maps" do
    socket = %Socket{assigns: assigns()}

    expected = %{
      organization_id: "org-1",
      mission_id: "mission-1",
      dashboard_id: "dashboard-1",
      document: assigns().dashboard_document,
      document_mode: :published,
      resolve_mode: :live_tick,
      scope_context: %{"primary" => %{"kind" => "spacecraft", "ids" => ["sc-1"]}},
      time_context: %{"mode" => "archive"},
      data_context: %{"realm" => "rehearsal"},
      limit_context: %{"semantics_mode" => "observed"}
    }

    assert RuntimeAssigns.engine_request_attrs(socket, :live_tick) == expected
    assert RuntimeAssigns.engine_request_attrs(assigns(), :live_tick) == expected
  end

  defp assigns do
    %{
      current_scope: %{organization_id: "org-1"},
      current_mission: %{mission_id: "mission-1"},
      dashboard_document: %Document{
        dashboard_id: "dashboard-1",
        organization_id: "org-1",
        mission_id: "mission-1",
        name: "Ops dashboard"
      },
      dashboard_engine_result: %{resolve_mode: :initial},
      dashboard_document_mode: :published,
      context_spacecraft_id: "sc-1",
      context_scope_kind: "spacecraft",
      context_scope_id: "sc-1",
      context_scope_ids: ["sc-1"],
      dashboard_scope_context: %{"primary" => %{"kind" => "spacecraft", "ids" => ["sc-1"]}},
      dashboard_time_mode: "archive",
      dashboard_time_from: "2026-01-01T00:00:00Z",
      dashboard_time_to: "2026-01-01T00:05:00Z",
      dashboard_replay_run_id: nil,
      dashboard_time_validation: "valid",
      dashboard_time_context: %{"mode" => "archive"},
      dashboard_runtime_context_since: ~U[2026-06-25 12:00:00Z],
      dashboard_data_realm: "rehearsal",
      dashboard_data_view: "as_recorded",
      dashboard_compare_data_view: "all_revisions",
      dashboard_data_source_id: "questdb-rehearsal",
      dashboard_source_binding_id: "rehearsal-binding",
      dashboard_data_context: %{"realm" => "rehearsal"},
      dashboard_limit_mode: "observed",
      dashboard_limit_context: %{"semantics_mode" => "observed"},
      dashboard_selected_data_ref: %{"target" => "telemetry_sample"},
      dashboard_selection_query: %{"selected_id" => "sample-1"},
      dashboard_evidence_query: nil,
      edit_mode?: false
    }
  end
end
