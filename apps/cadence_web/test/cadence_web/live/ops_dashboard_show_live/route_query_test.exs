defmodule CadenceWeb.OpsDashboardShowLive.RouteQueryTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{DataBinding, Document}
  alias CadenceWeb.OpsDashboardShowLive.RouteQuery

  test "merge compacts nil and empty overrides so route patches can clear params" do
    assert RouteQuery.merge(
             %{
               "panel" => "data_link",
               "selected_id" => "sample-1",
               "selected_target" => "telemetry_sample"
             },
             %{
               "selected_id" => nil,
               "time_mode" => "archive",
               "from" => "",
               "to" => "2026-06-26T12:00:00Z"
             }
           ) == %{
             "panel" => "data_link",
             "selected_target" => "telemetry_sample",
             "time_mode" => "archive",
             "to" => "2026-06-26T12:00:00Z"
           }
  end

  test "encode returns nil for empty query and URL encodes non-empty params" do
    assert RouteQuery.encode(%{}) == nil
    assert RouteQuery.encode(%{"selected_id" => nil}) == nil

    encoded =
      RouteQuery.encode(%{
        "panel" => "versions",
        "activity_event" => "dashboard event 1"
      })

    assert URI.decode_query(encoded) == %{
             "panel" => "versions",
             "activity_event" => "dashboard event 1"
           }
  end

  test "current_with merges overrides onto the dashboard runtime route query" do
    query =
      assigns(%{
        dashboard_selection_query: %{
          "selected_target" => "telemetry_sample",
          "selected_id" => "sample-1"
        }
      })
      |> RouteQuery.current_with(%{
        "selected_id" => nil,
        "compare_data_view" => "all_revisions"
      })

    assert query == %{
             "panel" => "data_link",
             "selected_target" => "telemetry_sample",
             "source_binding_id" => "primary",
             "compare_data_view" => "all_revisions"
           }
  end

  test "runtime_restore_overrides clears all runtime keys and restores only saved runtime values" do
    overrides =
      RouteQuery.runtime_restore_overrides(%{
        "time_mode" => "archive",
        "from" => "2026-06-26T12:00:00Z",
        "to" => "2026-06-26T12:05:00Z",
        "scope_kind" => "source_endpoint",
        "scope_ids" => "endpoint-alpha,endpoint-beta",
        "panel" => "data_link",
        "selected_id" => "sample-1"
      })

    assert Map.take(overrides, ["time_mode", "from", "to"]) == %{
             "time_mode" => "archive",
             "from" => "2026-06-26T12:00:00Z",
             "to" => "2026-06-26T12:05:00Z"
           }

    assert Map.take(overrides, ["scope_kind", "scope_ids"]) == %{
             "scope_kind" => "source_endpoint",
             "scope_ids" => "endpoint-alpha,endpoint-beta"
           }

    assert Map.take(overrides, ["panel", "selected_id"]) == %{}
    assert Map.keys(overrides) |> Enum.sort() == RouteQuery.runtime_query_keys() |> Enum.sort()
    assert overrides["replay_run_id"] == nil
    assert overrides["scope_id"] == nil
    assert overrides["source_binding_id"] == nil
  end

  defp assigns(overrides) do
    Map.merge(
      %{
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
        dashboard_compare_data_view: nil,
        dashboard_data_source_id: nil,
        dashboard_source_binding_id: nil,
        dashboard_limit_mode: "observed"
      },
      overrides
    )
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
