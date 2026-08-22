defmodule CadenceWeb.OpsDashboardShowLive.RuntimeControlsSelectionTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [assign: 3]

  alias Cadence.Dashboards.Document

  alias Cadence.DataSources.DataBinding
  alias CadenceWeb.OpsDashboardShowLive.RuntimeControls
  alias Phoenix.LiveView.Socket

  test "clear_data_selection closes data-link panels and clears route selection query" do
    socket =
      socket(%{
        panel: {:data_link, %{status: :resolved}},
        dashboard_selected_data_ref: %{"target" => "telemetry_sample"},
        dashboard_selection_query: %{"selected_id" => "sample-1"},
        dashboard_selection_state: "active"
      })

    socket = RuntimeControls.clear_data_selection(socket, patch_opts())

    assert socket.assigns.panel == nil
    assert socket.assigns.dashboard_selected_data_ref == nil
    assert socket.assigns.dashboard_selection_query == nil
    assert socket.assigns.dashboard_selection_state == "none"

    assert socket.assigns.patched_query == %{
             "panel" => nil,
             "selected_target" => nil,
             "selected_link" => nil,
             "selected_id" => nil,
             "selected_time" => nil,
             "selected_placement" => nil,
             "selected_data_view" => nil,
             "selected_series_role" => nil,
             "selected_compare_of" => nil,
             "selected_comparison_state" => nil,
             "selected_comparison_delta" => nil,
             "selected_primary_sample" => nil,
             "selected_compare_sample" => nil,
             "selected_primary_data_view" => nil,
             "selected_compare_data_view" => nil,
             "selected_primary_data_management" => nil,
             "selected_compare_data_management" => nil,
             "selected_primary_count" => nil,
             "selected_compare_count" => nil,
             "selected_widget" => nil,
             "selected_widget_title" => nil,
             "selected_widget_type" => nil,
             "selected_widget_source" => nil,
             "selected_primary_kind" => nil,
             "selected_compare_kind" => nil,
             "selected_primary_observables" => nil,
             "selected_compare_observables" => nil,
             "selected_scope_kind" => nil,
             "selected_scope_id" => nil,
             "selected_scope_ids" => nil,
             "selected_resource_id" => nil,
             "selected_spacecraft_id" => nil,
             "selected_contact_id" => nil,
             "selected_contact_ids" => nil,
             "selected_transport_id" => nil,
             "selected_source_endpoint_id" => nil,
             "selected_ground_station_id" => nil,
             "selected_scope_link_id" => nil,
             "nav_from_link_id" => nil,
             "nav_from_target" => nil,
             "nav_from_target_id" => nil,
             "nav_from_label" => nil,
             "nav_from_relationship_kind" => nil,
             "nav_from_relationship_label" => nil,
             "nav_trail" => nil,
             "time_axis" => nil
           }
  end

  defp patch_opts do
    [
      patch: fn socket, query -> assign(socket, :patched_query, query) end,
      valid_contact?: fn _scope, _mission, _contact_id -> false end
    ]
  end

  defp socket(assigns) do
    %Socket{
      assigns:
        Map.merge(
          %{
            __changed__: %{},
            flash: %{},
            current_scope: %{organization_id: "org-1"},
            current_mission: %{mission_id: "mission-1"},
            spacecraft: [%{spacecraft_id: "sc-1"}],
            dashboard_document: document(),
            dashboard_data_realms: ["flight"],
            dashboard_data_bindings: [data_binding()],
            dashboard_selected_data_ref: nil,
            dashboard_selection_query: nil,
            dashboard_evidence_query: nil,
            context_scope_kind: nil,
            context_scope_id: nil,
            dashboard_time_mode: "live",
            dashboard_time_from: nil,
            dashboard_time_to: nil,
            dashboard_replay_run_id: nil,
            dashboard_data_realm: "flight",
            dashboard_data_view: "canonical",
            dashboard_data_source_id: nil,
            dashboard_source_binding_id: nil,
            dashboard_limit_mode: "observed",
            dashboard_selection_state: "none",
            panel: nil
          },
          assigns
        )
    }
  end

  defp document do
    %Document{
      defaults: %{
        "data" => %{
          "realm" => "flight",
          "source_mode" => "specific",
          "source_contexts" => %{
            "telemetry" => %{"source_binding_id" => "flight-binding"}
          },
          "view" => "canonical"
        }
      }
    }
  end

  defp data_binding(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        binding_id: "flight-binding",
        data_source_id: "questdb-flight",
        dataset: "flight",
        realm: :flight,
        logical_source: :telemetry,
        priority: 0,
        status: :active
      })

    struct!(DataBinding, attrs)
  end
end
