defmodule CadenceWeb.OpsDashboardShowLive.SourcePresentationDashboardWarningsTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{DashboardAction, DashboardResolveResult, ResolveWarning}
  alias CadenceWeb.OpsDashboardShowLive.SourcePresentation

  test "dashboard warning summaries preserve typed telemetry actions" do
    action = %DashboardAction{
      action_id: "telemetry-warning-explore:req-telemetry:HK.counter",
      label: "Explore telemetry",
      target: :telemetry_explore,
      kind: :invoke,
      query: %{"point_id" => "HK.counter", "realm" => "flight"},
      source: :warning
    }

    result = %DashboardResolveResult{
      dashboard_warnings: [
        %ResolveWarning{
          code: :unsupported_time_axis,
          severity: :warning,
          details: %{
            source_request_id: "req-telemetry",
            point_id: "HK.counter",
            requested_axis: :generation_time,
            fallback_axis: :receipt_time,
            supported_time_axes: [:receipt_time],
            actions: [action]
          }
        }
      ]
    }

    assert [%{actions: actions, detail_rows: detail_rows}] =
             SourcePresentation.dashboard_warning_summaries(result)

    assert Enum.any?(actions, fn
             %DashboardAction{
               action_id: "telemetry-warning-explore:req-telemetry:HK.counter",
               target: :telemetry_explore,
               kind: :invoke,
               query: %{"point_id" => "HK.counter", "realm" => "flight"},
               source: :warning
             } ->
               true

             _action ->
               false
           end)

    refute Enum.any?(detail_rows, &(&1.label =~ "Actions"))
    assert %{value: "generation_time"} = Enum.find(detail_rows, &(&1.label == "Requested axis"))
    assert %{value: "receipt_time"} = Enum.find(detail_rows, &(&1.label == "Executed axis"))
    assert %{value: "receipt_time"} = Enum.find(detail_rows, &(&1.label == "Supported axes"))
  end

  test "dashboard warning summaries label non-canonical data views" do
    result = %DashboardResolveResult{
      dashboard_warnings: [
        %ResolveWarning{
          code: :all_revisions_view,
          severity: :warning,
          message: "Telemetry source is showing all observation revisions",
          details: %{
            data_view: :all_revisions,
            canonical_default?: false,
            point_id: "HK.counter"
          }
        }
      ]
    }

    assert [
             %{
               code: :all_revisions_view,
               label: "All revisions",
               severity: :warning,
               detail_rows: detail_rows
             }
           ] = SourcePresentation.dashboard_warning_summaries(result)

    assert %{value: "all_revisions"} = Enum.find(detail_rows, &(&1.label == "Data view"))
    assert %{value: "false"} = Enum.find(detail_rows, &(&1.label == "Canonical default?"))
    assert %{value: "HK.counter"} = Enum.find(detail_rows, &(&1.label == "Point id"))
  end

  test "dashboard warning summaries do not synthesize fallback source actions" do
    result = %DashboardResolveResult{
      dashboard_warnings: [
        %ResolveWarning{
          code: :missing_source_binding,
          severity: :error,
          details: %{
            logical_source: :telemetry,
            realm: :flight,
            data_source_id: "flight-questdb"
          }
        }
      ]
    }

    assert [%{actions: [], detail_rows: detail_rows}] =
             SourcePresentation.dashboard_warning_summaries(result)

    refute Enum.any?(detail_rows, &(&1.label =~ "Actions"))
  end

  test "dashboard warning summaries explain historical source binding misses" do
    result = %DashboardResolveResult{
      dashboard_warnings: [
        %ResolveWarning{
          code: :missing_source_binding,
          severity: :error,
          details: %{
            logical_source: :telemetry,
            realm: :flight,
            source_binding_at: ~U[2026-06-21 19:30:00Z],
            source_binding_miss_reason: :source_binding_not_started_at_requested_time,
            nearest_source_binding_id: "mission-flight-telemetry",
            nearest_data_source_id: "mission-questdb-v1",
            nearest_source_binding_started_at: ~U[2026-06-21 20:00:00Z],
            nearest_source_binding_ended_at: ~U[2026-06-21 21:00:00Z]
          }
        }
      ]
    }

    assert [%{detail_rows: detail_rows}] = SourcePresentation.dashboard_warning_summaries(result)

    assert %{value: "2026-06-21T19:30:00Z"} =
             Enum.find(detail_rows, &(&1.label == "Source binding at"))

    assert %{value: "source_binding_not_started_at_requested_time"} =
             Enum.find(detail_rows, &(&1.label == "Source binding miss reason"))

    assert %{value: "mission-flight-telemetry"} =
             Enum.find(detail_rows, &(&1.label == "Nearest source binding id"))

    assert %{value: "mission-questdb-v1"} =
             Enum.find(detail_rows, &(&1.label == "Nearest data source id"))

    assert %{value: "2026-06-21T20:00:00Z"} =
             Enum.find(detail_rows, &(&1.label == "Nearest source binding started at"))

    assert %{value: "2026-06-21T21:00:00Z"} =
             Enum.find(detail_rows, &(&1.label == "Nearest source binding ended at"))
  end
end
