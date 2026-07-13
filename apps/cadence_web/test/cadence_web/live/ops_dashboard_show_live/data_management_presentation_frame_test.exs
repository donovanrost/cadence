defmodule CadenceWeb.OpsDashboardShowLive.DataManagementPresentationFrameTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.Frame
  alias CadenceWeb.OpsDashboardShowLive.DataManagementPresentation

  test "frame summarizes data view, realm, replay, and revision badges" do
    frame = %Frame{
      meta: %{
        data_view: :as_recorded,
        realm: :simulation,
        replay_run_id: "replay-1",
        warning_codes: ["corrected-range", :partial_data]
      }
    }

    assert %{
             data_view: "as_recorded",
             warning_codes: ["corrected_range", "partial_data"],
             badges: badges
           } = DataManagementPresentation.frame(frame)

    assert badge?(badges, :data_view, "as_recorded", "as_recorded_view")
    assert badge?(badges, :realm, "simulation", "simulation_data")
    assert badge?(badges, :time_mode, "replay_run", "replay_data")
    assert badge?(badges, :revision_state, "corrected", "corrected_range")
    assert badge?(badges, :revision_state, "partial", "partial_data")
  end

  test "frame falls back to source request context" do
    frame = %Frame{
      meta: %{
        source_request_context: %{
          requested_data_view: :recomputed,
          requested_realm: :replay,
          time_mode: :replay_run
        }
      }
    }

    assert %{
             data_view: "recomputed",
             badges: [
               %{kind: :data_view, value: "recomputed"},
               %{kind: :realm, value: "replay"},
               %{kind: :time_mode, value: "replay_run"}
             ]
           } = DataManagementPresentation.frame(frame)
  end

  test "frame summarizes analysis basis and source-health evidence" do
    frame = %Frame{
      meta: %{
        analysis_basis: :recomputed_analysis,
        source_health: :degraded,
        source_health_reason: :source_schema_probe_failed,
        source_health_freshness: :fresh,
        source_health_age_ms: 250,
        source_health_max_age_ms: 60_000,
        source_health_event_id: "source-health-event-1",
        realm: :flight,
        data_view: :canonical,
        data_source_id: "questdb-flight",
        source_binding_id: "flight-telemetry",
        time_mode: :archive,
        time_axis: :occurred_at
      }
    }

    assert %{badges: badges} = DataManagementPresentation.frame(frame)

    assert badge?(
             badges,
             :analysis_basis,
             "recomputed_analysis",
             "recomputed_analysis"
           )

    assert Enum.any?(
             badges,
             &match?(
               %{
                 kind: :source_health,
                 value: "degraded",
                 label: "Source degraded",
                 status: :warning,
                 code: "source_schema_probe_failed",
                 data_link_target: :source_health_event,
                 data_link_id: "source-health-event-1",
                 realm: "flight",
                 data_view: "canonical",
                 data_source_id: "questdb-flight",
                 source_binding_id: "flight-telemetry",
                 time_mode: "archive",
                 time_axis: "occurred_at",
                 summary:
                   "reason source_schema_probe_failed; freshness fresh; age 250ms of 60000ms"
               },
               &1
             )
           )
  end

  test "frame omits nominal source-health evidence" do
    frame = %Frame{
      meta: %{
        analysis_basis: :recomputed_analysis,
        source_health: :healthy,
        source_health_freshness: :fresh,
        source_health_event_id: "source-health-event-1"
      }
    }

    assert %{badges: badges} = DataManagementPresentation.frame(frame)
    refute Enum.any?(badges, &(&1.kind == :source_health))
  end

  test "frame derives revision badges from structured revision state" do
    frame = %Frame{
      meta: %{
        revision_state: %{
          "advisory_count" => "1",
          superseded_count: 2,
          has_conflicts?: true,
          has_duplicates?: true,
          identity_count: 4
        }
      }
    }

    assert %{warning_codes: [], badges: badges} = DataManagementPresentation.frame(frame)

    assert badge?(badges, :revision_state, "corrected", "corrected_range")
    assert badge?(badges, :revision_state, "backfill", "advisory_backfill")
    assert badge?(badges, :revision_state, "conflict", "conflicting_observations")
    refute badge?(badges, :revision_state, "mixed", "mixed_revisions")
  end

  test "frame summarizes active historical workflow metadata" do
    frame = %Frame{
      meta: %{
        historical_workflows: [
          %{
            category: :telemetry_backfill,
            kind: :backfill_started,
            source_record_id: "backfill-event-1",
            realm: :replay,
            requested_data_view: :all_revisions,
            requested_data_source_id: "questdb-replay",
            requested_source_binding_id: "binding-replay",
            time_mode: :replay_run,
            time_axis: :generation_time,
            replay_run_id: "replay-run-1"
          }
        ],
        active_historical_workflows: [
          %{"category" => "telemetry_revision", "kind" => "mark_conflict"},
          %{
            "category" => "source_watermark",
            "kind" => "advanced",
            "source_record_id" => "watermark-event-1"
          }
        ],
        historical_workflow_outcomes: [
          %{
            category: :telemetry_backfill,
            kind: :late_data_rejected,
            source_record_id: "late-data-event-1",
            selected_sample_count: 1,
            projection_effect: :history_only,
            write_validity_state: :late_rejected,
            record_current_values: false,
            refresh_latest_value: false
          }
        ]
      }
    }

    assert %{badges: badges} = DataManagementPresentation.frame(frame)

    assert badge?(badges, :historical_workflow, "backfill_started", "backfill_started")
    assert badge?(badges, :historical_workflow, "correction_conflict", "mark_conflict")
    assert badge?(badges, :source_freshness, "advanced", "advanced")
    assert badge?(badges, :historical_workflow, "late_data_rejected", "late_data_rejected")

    assert Enum.any?(
             badges,
             &match?(
               %{
                 value: "backfill_started",
                 data_link_target: :telemetry_backfill_lifecycle_event,
                 data_link_id: "backfill-event-1",
                 realm: "replay",
                 data_view: "all_revisions",
                 data_source_id: "questdb-replay",
                 source_binding_id: "binding-replay",
                 time_mode: "replay_run",
                 time_axis: "generation_time",
                 replay_run_id: "replay-run-1"
               },
               &1
             )
           )

    assert Enum.any?(
             badges,
             &match?(
               %{
                 value: "advanced",
                 data_link_target: :source_watermark_event,
                 data_link_id: "watermark-event-1"
               },
               &1
             )
           )

    assert Enum.any?(
             badges,
             &match?(
               %{
                 value: "late_data_rejected",
                 data_link_target: :telemetry_backfill_lifecycle_event,
                 data_link_id: "late-data-event-1",
                 selected_sample_count: 1,
                 projection_effect: :history_only,
                 write_validity_state: :late_rejected,
                 record_current_values: false,
                 refresh_latest_value: false,
                 summary:
                   "1 selected sample; writes late_rejected history; does not refresh current/latest; effect history_only"
               },
               &1
             )
           )
  end

  defp badge?(badges, kind, value, code) do
    Enum.any?(badges, &match?(%{kind: ^kind, value: ^value, code: ^code}, &1))
  end
end
