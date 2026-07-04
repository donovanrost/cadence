defmodule CadenceWeb.OpsDashboardShowLive.DataViewComparisonTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{DataContext, Document, PlacementFrames}
  alias CadenceWeb.OpsDashboardShowLive.DataViewComparison
  alias Phoenix.LiveView.Socket

  test "builds a comparison request by replacing only the data view" do
    request =
      assigns(%{
        dashboard_data_view: "all_revisions",
        dashboard_compare_data_view: "canonical",
        dashboard_data_context: %{
          "realm" => "flight",
          "view" => "all_revisions",
          "source_mode" => "primary"
        }
      })
      |> DataViewComparison.request(:context_change)

    assert request.data_context == %{
             "realm" => "flight",
             "source_mode" => "primary",
             "view" => "canonical"
           }

    assert request.resolve_mode == :context_change
  end

  test "preserves non-spacecraft scope while building comparison requests" do
    scope_context = %{
      "primary" => %{
        "kind" => "source_endpoint",
        "mode" => "one",
        "ids" => ["source-endpoint-alpha"]
      }
    }

    request =
      assigns(%{
        dashboard_scope_context: scope_context,
        dashboard_data_view: "all_revisions",
        dashboard_compare_data_view: "canonical",
        dashboard_data_context: %{
          "realm" => "flight",
          "view" => "all_revisions",
          "source_mode" => "primary",
          "source_contexts" => %{
            "telemetry" => %{
              "source_binding_id" => "default_flight_telemetry"
            }
          }
        }
      })
      |> DataViewComparison.request(:context_change)

    assert request.scope_context == scope_context

    assert request.data_context == %{
             "realm" => "flight",
             "source_mode" => "primary",
             "source_contexts" => %{
               "telemetry" => %{
                 "source_binding_id" => "default_flight_telemetry"
               }
             },
             "view" => "canonical"
           }

    assert request.time_context == %{}
    assert request.limit_context == %{}
    assert request.resolve_mode == :context_change
  end

  test "returns nil when comparison view is absent or matches the active view" do
    refute DataViewComparison.request(assigns(%{dashboard_compare_data_view: nil}), :initial)

    refute DataViewComparison.request(
             assigns(%{
               dashboard_data_view: "canonical",
               dashboard_compare_data_view: "canonical"
             }),
             :initial
           )
  end

  test "supports already-normalized data contexts" do
    request =
      assigns(%{
        dashboard_data_view: "canonical",
        dashboard_compare_data_view: "all_revisions",
        dashboard_data_context: %DataContext{realm: "flight", view: "canonical"}
      })
      |> DataViewComparison.request(:initial)

    assert %DataContext{realm: "flight", view: "all_revisions"} = request.data_context
  end

  test "assigns comparison result and frames" do
    result = %{frames_by_placement: %{"placement-1" => %PlacementFrames{}}}
    socket = %Socket{assigns: %{__changed__: %{}}}

    socket = DataViewComparison.assign_result(socket, result)

    assert socket.assigns.dashboard_compare_engine_result == result

    assert socket.assigns.dashboard_compare_engine_frames_by_placement ==
             result.frames_by_placement

    socket = DataViewComparison.assign_result(socket, nil)

    refute socket.assigns.dashboard_compare_engine_result
    assert socket.assigns.dashboard_compare_engine_frames_by_placement == %{}
  end

  defp assigns(overrides) do
    Map.merge(
      %{
        current_scope: %{organization_id: "org-1"},
        current_mission: %{mission_id: "mission-1"},
        dashboard_document: %Document{dashboard_id: "dashboard-1"},
        dashboard_document_mode: :draft,
        dashboard_scope_context: %{},
        dashboard_time_context: %{},
        dashboard_data_context: %{"realm" => "flight", "view" => "canonical"},
        dashboard_limit_context: %{},
        dashboard_data_view: "canonical",
        dashboard_compare_data_view: nil
      },
      overrides
    )
  end
end
