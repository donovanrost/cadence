defmodule CadenceWeb.OpsDashboardShowLive.NavigationTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [assign: 3]

  alias Cadence.Dashboards.Document

  alias Cadence.DataSources.DataBinding
  alias CadenceWeb.OpsDashboardShowLive.Navigation
  alias Phoenix.LiveView.Socket

  test "show_path returns the dashboard path when the current query is empty" do
    assert Navigation.show_path(compact_socket()) ==
             "/missions/mission-1/ops/dashboards/dashboard-1"
  end

  test "show_path merges compact route overrides onto the current query" do
    path =
      socket(%{
        dashboard_selection_query: %{
          "selected_target" => "telemetry_sample",
          "selected_id" => "sample-1"
        }
      })
      |> Navigation.show_path(%{
        "time_mode" => "archive",
        "from" => "2026-06-25T11:55:00Z",
        "to" => "2026-06-25T12:00:00Z",
        "selected_id" => nil
      })

    uri = URI.parse(path)

    assert uri.path == "/missions/mission-1/ops/dashboards/dashboard-1"

    assert URI.decode_query(uri.query) == %{
             "from" => "2026-06-25T11:55:00Z",
             "panel" => "data_link",
             "selected_target" => "telemetry_sample",
             "source_binding_id" => "primary",
             "time_mode" => "archive",
             "to" => "2026-06-25T12:00:00Z"
           }
  end

  test "show_path accepts assigns maps" do
    assert Navigation.show_path(compact_socket().assigns) ==
             "/missions/mission-1/ops/dashboards/dashboard-1"
  end

  test "patch supports callback injection for focused tests" do
    socket =
      Navigation.patch(
        socket(),
        %{"time_mode" => "archive"},
        patch: fn socket, query -> assign(socket, :patched_query, query) end
      )

    assert socket.assigns.patched_query == %{"time_mode" => "archive"}
  end

  defp socket(assigns \\ %{}) do
    %Socket{
      assigns:
        Map.merge(
          %{
            __changed__: %{},
            current_mission: %{mission_id: "mission-1"},
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
            dashboard_limit_mode: "observed"
          },
          assigns
        )
    }
  end

  defp compact_socket do
    socket(%{
      dashboard_document: %Document{dashboard_id: "dashboard-1", defaults: %{}},
      dashboard_data_bindings: []
    })
  end

  defp document do
    %Document{
      dashboard_id: "dashboard-1",
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
