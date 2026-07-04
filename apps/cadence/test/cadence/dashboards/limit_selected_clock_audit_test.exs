defmodule Cadence.Dashboards.LimitSelectedClockAuditTest do
  use Cadence.DataCase, async: false

  alias Cadence.Dashboards.{
    DashboardResolveRequest,
    DataContext,
    Document,
    Field,
    Frame,
    LimitSelectedClockAudit,
    PlannedSourceRequest,
    ResolveWarning,
    SourceResult,
    TimeContext
  }

  @organization_id "org-dashboard-limit-clock-audit"
  @mission_id "mission-dashboard-limit-clock-audit"
  @observed_at ~U[2026-06-28 16:00:00Z]

  setup do
    persist_mission_scope(@organization_id, @mission_id)
    :ok
  end

  test "builds selected-clock operational events for non-observed limit frames" do
    request = resolve_request()
    source_request = limits_source_request()
    source_result = limits_source_result(:recomputed)

    assert [event] =
             LimitSelectedClockAudit.events(request, source_request, source_result,
               observed_at: @observed_at
             )

    assert event.event_id =~ "operational_event:dashboard_limit_selected_clock:"
    assert event.organization_id == @organization_id
    assert event.mission_id == @mission_id
    assert event.category == :limits
    assert event.kind == :dashboard_limit_selected_clock
    assert event.severity == :warning
    assert event.subject == %{kind: :telemetry_point, id: "HK.counter"}
    assert event.occurred_at == @observed_at
    assert event.recorded_at == @observed_at
    assert event.effective_at == ~U[2026-06-28 15:58:00Z]
    assert event.scope.point_id == "HK.counter"
    assert event.scope.data_realm == :flight
    assert event.scope.data_source_id == "flight-questdb"
    assert event.scope.source_binding_id == "flight-telemetry"
    assert event.scope.dashboard_id == "dashboard-limit-clock-audit"

    assert event.causality.correlation_id ==
             "dashboard-limit-clock-audit:limits-primary:HK.counter"

    assert event.causality.replay_run_id == "replay-a"
    refute Map.has_key?(event.causality, :source_record_kind)
    assert event.payload.selected_limit_clock.receipt_time == "sample-receipt"
    assert event.payload.selected_limit_definition_intervals == [%{definition_id: "limits-v2"}]
    assert event.payload.missing_sample_ids == ["sample-missing"]
    assert event.current.selected_limit_clock.receipt_time == "sample-receipt"
    assert event.current.semantics_mode == :recomputed
    assert event.current.warning_codes == [:incomplete_limit_evaluation]
  end

  test "persists selected-clock operational events with deterministic upsert semantics" do
    request = resolve_request()
    source_request = limits_source_request()
    source_result = limits_source_result(:compare)

    assert %{event_ids: [event_id], errors: []} =
             LimitSelectedClockAudit.persist_source_results(
               request,
               [{source_request, source_result}],
               observed_at: @observed_at
             )

    assert %{event_ids: [^event_id], errors: []} =
             LimitSelectedClockAudit.persist_source_results(
               request,
               [{source_request, source_result}],
               observed_at: DateTime.add(@observed_at, 5, :second)
             )

    assert [event] =
             Cadence.list_operational_events(@organization_id, @mission_id,
               category: :limits,
               kind: :dashboard_limit_selected_clock,
               subject_kind: :telemetry_point,
               subject_id: "HK.counter"
             )

    assert event.event_id == event_id
    assert DateTime.compare(event.occurred_at, DateTime.add(@observed_at, 5, :second)) == :eq
    assert event.severity == :warning
    assert event.scope["logical_source"] == "limits"
    assert event.scope["data_realm"] == "flight"
    assert event.scope["data_source_id"] == "flight-questdb"
    assert event.scope["source_binding_id"] == "flight-telemetry"
    assert event.scope["replay_run_id"] == "replay-a"
    assert event.payload["semantics_mode"] == "compare"
    assert event.payload["selected_limit_clock"] == %{"receipt_time" => "sample-receipt"}
    assert event.payload["missing_sample_ids"] == ["sample-missing"]
    assert event.current["selected_limit_clock"] == %{"receipt_time" => "sample-receipt"}
    assert event.current["warning_codes"] == ["incomplete_limit_evaluation"]
    assert event.metadata["source"] == "dashboard_limit_selected_clock_audit"
    assert event.metadata["deterministic?"] == true
  end

  test "does not audit observed limit frames" do
    assert [] =
             LimitSelectedClockAudit.events(
               resolve_request(),
               limits_source_request(),
               limits_source_result(:observed),
               observed_at: @observed_at
             )
  end

  defp resolve_request do
    %DashboardResolveRequest{
      organization_id: @organization_id,
      mission_id: @mission_id,
      dashboard_id: "dashboard-limit-clock-audit",
      document: %Document{
        organization_id: @organization_id,
        mission_id: @mission_id,
        dashboard_id: "dashboard-limit-clock-audit",
        name: "Limit Clock Audit"
      },
      time_context: %TimeContext{
        mode: :range,
        axis: :receipt_time,
        to: ~U[2026-06-28 16:00:00Z],
        replay_run_id: "replay-a"
      },
      data_context: %DataContext{
        realm: :flight,
        data_source_id: "flight-questdb",
        source_binding_id: "flight-telemetry",
        dataset: "flight",
        replay_run_id: "replay-a"
      }
    }
  end

  defp limits_source_request do
    %PlannedSourceRequest{
      organization_id: @organization_id,
      mission_id: @mission_id,
      request_id: "limits-primary",
      logical_source: :limits,
      observables: ["HK.counter"],
      time_context: %TimeContext{
        mode: :range,
        axis: :receipt_time,
        to: ~U[2026-06-28 16:00:00Z],
        replay_run_id: "replay-a"
      },
      data_context: %DataContext{
        realm: :flight,
        data_source_id: "flight-questdb",
        source_binding_id: "flight-telemetry",
        dataset: "flight",
        replay_run_id: "replay-a"
      },
      sampling: %{mode: :latest_state}
    }
  end

  defp limits_source_result(semantics_mode) do
    %SourceResult{
      request_id: "limits-primary",
      frames: [
        %Frame{
          frame_id: "frame-limits-HK-counter",
          source: :limits,
          shape: :wide,
          time_axis: :receipt_time,
          fields: [
            %Field{
              name: "time",
              kind: :time,
              values: [~U[2026-06-28 15:58:00Z]]
            }
          ],
          meta: %{
            observable_id: "HK.counter",
            semantics_mode: semantics_mode,
            selected_limit_clock: %{receipt_time: "sample-receipt"},
            selected_limit_definition_intervals: [%{definition_id: "limits-v2"}],
            analysis_basis: :selected_clock,
            sampling: %{mode: :latest_state},
            realm: :flight,
            data_source_id: "flight-questdb",
            source_binding_id: "flight-telemetry",
            dataset: "flight",
            replay_run_id: "replay-a",
            source_sample_count: 1,
            observed_event_count: 1,
            divergence_count: 1
          }
        }
      ],
      warnings: [
        %ResolveWarning{
          code: :incomplete_limit_evaluation,
          severity: :warning,
          scope: :frame,
          frame_id: "frame-limits-HK-counter",
          details: %{
            missing_sample_ids: ["sample-missing"]
          }
        }
      ],
      meta: %{
        data_source_id: "flight-questdb",
        source_binding_id: "flight-telemetry"
      }
    }
  end
end
