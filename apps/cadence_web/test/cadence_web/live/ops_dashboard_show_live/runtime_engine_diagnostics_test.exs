defmodule CadenceWeb.OpsDashboardShowLive.RuntimeEngineDiagnosticsTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{DashboardResolveResult, PlannedSourceRequest, ResolveWarning}

  alias Cadence.DataSources.SourceWatermark

  alias CadenceWeb.OpsDashboardShowLive.RuntimeEngineDiagnostics

  test "rows expose resolve metadata, cache status, and request contexts" do
    result = engine_result()

    assert RuntimeEngineDiagnostics.rows(result) == [
             %{label: "Resolve", value: "context_change"},
             %{label: "Source requests", value: "3"},
             %{label: "Executed requests", value: "2"},
             %{label: "Skipped requests", value: "1"},
             %{label: "Plan cache", value: "hit"},
             %{label: "Source cache", value: "hit stale"},
             %{label: "Frame cache", value: "miss"},
             %{label: "Source dependencies", value: "limits->telemetry:latest_sample"},
             %{label: "Source dependency evidence", value: "-"},
             %{label: "Time", value: "archive"},
             %{label: "Realm", value: "flight"},
             %{label: "Limits", value: "observed"},
             %{label: "Snapshot", value: "true"},
             %{label: "Live append", value: "false"}
           ]
  end

  test "engine field helpers tolerate missing engine results" do
    assert RuntimeEngineDiagnostics.resolve_mode(nil) == nil
    assert RuntimeEngineDiagnostics.metadata(nil, :source_request_count) == nil
    assert RuntimeEngineDiagnostics.cache_status(nil, :plan_cache) == nil
    assert RuntimeEngineDiagnostics.source_cache_statuses(nil) == nil
    assert RuntimeEngineDiagnostics.frame_cache_statuses(nil) == nil
    assert RuntimeEngineDiagnostics.source_dependency_count(nil) == 0
    assert RuntimeEngineDiagnostics.source_dependency_summary(nil) == nil
    assert RuntimeEngineDiagnostics.source_dependency_evidence_summary(nil) == nil
    assert RuntimeEngineDiagnostics.source_dependency_degraded_count(nil) == 0
    assert RuntimeEngineDiagnostics.boolean_metadata(nil, :snapshot?) == nil
    assert RuntimeEngineDiagnostics.context(nil, :time, :mode) == nil
  end

  test "context reads time, data source, and limit semantics" do
    result = engine_result()

    assert RuntimeEngineDiagnostics.context(result, :time, :mode) == "archive"
    assert RuntimeEngineDiagnostics.context(result, :data, :realm) == "flight"
    assert RuntimeEngineDiagnostics.context(result, :data, :data_source_id) == "questdb-flight"
    assert RuntimeEngineDiagnostics.context(result, :data, :source_binding_id) == "flight-binding"
    assert RuntimeEngineDiagnostics.context(result, :data, :view) == "canonical"
    assert RuntimeEngineDiagnostics.context(result, :limit, :semantics_mode) == "observed"
    assert RuntimeEngineDiagnostics.source_dependency_count(result) == 1

    assert RuntimeEngineDiagnostics.source_dependency_summary(result) ==
             "limits->telemetry:latest_sample"
  end

  test "source dependency evidence joins upstream source execution and watermark state" do
    result = dependency_evidence_result()

    assert RuntimeEngineDiagnostics.source_dependency_evidence_summary(result) ==
             "limits:req-limits->telemetry:req-telemetry:source_degraded:wait_for_source_health:stale"

    assert RuntimeEngineDiagnostics.source_dependency_degraded_count(result) == 1

    assert Enum.any?(
             RuntimeEngineDiagnostics.rows(result),
             &(&1 == %{
                 label: "Source dependency evidence",
                 value:
                   "limits:req-limits->telemetry:req-telemetry:source_degraded:wait_for_source_health:stale"
               })
           )
  end

  defp engine_result do
    %{
      resolve_mode: :context_change,
      plan_metadata: %{
        source_request_count: 3,
        executed_source_request_count: 2,
        skipped_source_request_count: 1,
        snapshot?: true,
        live_append_eligible?: false,
        time: %{mode: "archive", replay_run_id: nil},
        cache: %{
          plan_cache: %{status: :hit},
          source_result_cache_by_request_id: %{
            "req-1" => %{status: :stale},
            "req-2" => %{status: :hit}
          },
          frame_cache_by_placement: %{
            "placement-1" => %{
              "req-1" => %{status: :miss}
            }
          }
        }
      },
      planned_source_requests: [
        %{
          request_id: "req-1",
          logical_source: :telemetry,
          data_context: %{
            realm: "flight",
            source_contexts: %{
              telemetry: %{
                data_source_id: "questdb-flight",
                source_binding_id: "flight-binding",
                view: "canonical"
              }
            }
          },
          limit_context: %{semantics_mode: "observed"}
        },
        %{
          request_id: "req-limits",
          logical_source: :limits,
          source_dependencies: [
            %{
              logical_source: :telemetry,
              reason: :limit_latest_sample_input,
              products: [:latest_sample],
              sampling: %{mode: :latest}
            }
          ],
          data_context: %{
            realm: "flight"
          },
          limit_context: %{semantics_mode: "compare"}
        }
      ]
    }
  end

  defp dependency_evidence_result do
    %DashboardResolveResult{
      resolve_mode: :context_change,
      planned_source_requests: [
        %PlannedSourceRequest{
          request_id: "req-telemetry",
          logical_source: :telemetry,
          data_context: %{
            realm: :flight,
            source_contexts: %{
              telemetry: %{
                data_source_id: "questdb-flight",
                source_binding_id: "flight-binding",
                view: :canonical
              }
            }
          }
        },
        %PlannedSourceRequest{
          request_id: "req-limits",
          logical_source: :limits,
          source_dependencies: [
            %{
              logical_source: :telemetry,
              reason: :limit_latest_sample_input,
              products: [:latest_sample],
              sampling: %{mode: :latest}
            }
          ],
          data_context: %{realm: :flight},
          limit_context: %{semantics_mode: :compare}
        }
      ],
      watermarks: [
        %SourceWatermark{
          logical_source: :telemetry,
          request_id: "req-telemetry",
          confidence: :authoritative,
          freshness_state: :stale
        }
      ],
      plan_metadata: %{
        cache: %{
          source_result_cache_by_request_id: %{
            "req-telemetry" => %{status: :stale, reasons: [:source_degraded]}
          }
        }
      },
      dashboard_warnings: [
        %ResolveWarning{
          code: :source_degraded,
          severity: :warning,
          details: %{source_request_id: "req-telemetry"}
        }
      ]
    }
  end
end
