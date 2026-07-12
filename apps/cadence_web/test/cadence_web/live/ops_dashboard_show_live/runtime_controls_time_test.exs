defmodule CadenceWeb.OpsDashboardShowLive.RuntimeControlsTimeTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [assign: 3]

  alias Cadence.Dashboards.{DataBinding, Document}
  alias CadenceWeb.OpsDashboardShowLive.RuntimeControls
  alias Phoenix.LiveView.Socket

  test "time presets clear active selection and patch an archive window" do
    socket =
      socket(%{
        panel: {:data_link, %{status: :resolved}},
        dashboard_selected_data_ref: %{"target" => "telemetry_sample"},
        dashboard_selection_query: %{"selected_id" => "sample-1"},
        dashboard_selection_state: "active"
      })

    socket =
      RuntimeControls.set_time_preset(
        socket,
        "last_5m",
        Keyword.merge(patch_opts(), now: ~U[2026-06-25 12:00:00Z])
      )

    assert socket.assigns.dashboard_selected_data_ref == nil
    assert socket.assigns.dashboard_selection_query == nil
    assert socket.assigns.dashboard_selection_state == "none"

    assert socket.assigns.patched_query == %{
             "time_mode" => "archive",
             "time_axis" => nil,
             "from" => "2026-06-25T11:55:00Z",
             "to" => "2026-06-25T12:00:00Z",
             "replay_run_id" => nil
           }
  end

  test "pause_at_selected_time patches a centered archive range" do
    socket =
      socket(%{
        dashboard_selected_data_ref: %{
          "timestamp_ms" => DateTime.to_unix(~U[2026-06-25 12:00:00Z], :millisecond)
        }
      })

    socket = RuntimeControls.pause_at_selected_time(socket, patch_opts())

    assert socket.assigns.patched_query == %{
             "time_mode" => "archive",
             "from" => "2026-06-25T11:57:30.000Z",
             "to" => "2026-06-25T12:02:30.000Z"
           }
  end

  test "pause_at_selected_time reports a missing timestamped selection" do
    socket = RuntimeControls.pause_at_selected_time(socket(), patch_opts())

    assert socket.assigns.flash["error"] == "Select a timestamped dashboard datum first."
  end

  defp patch_opts do
    [
      patch: fn socket, query -> assign(socket, :patched_query, query) end,
      valid_contact?: fn _scope, _mission, _contact_id -> false end
    ]
  end

  defp socket(assigns \\ %{}) do
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
