defmodule CadenceWeb.OpsDashboardShowLive.EventTimelineDataTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{DataLink, Field, Frame, PlacementFrames}
  alias CadenceWeb.OpsDashboardShowLive.EventTimelineData

  test "rows renders events and intervals in occurrence order" do
    placement_frames = %PlacementFrames{
      primary: [
        %Frame{
          source: :events,
          shape: :events,
          fields: [
            %Field{name: "occurred_at", kind: :time, values: [~U[2026-06-17 12:05:00Z]]},
            %Field{name: "category", kind: :enum, values: [:mission_timeline]},
            %Field{name: "kind", kind: :enum, values: [:operator_note]},
            %Field{name: "severity", kind: :enum, values: [:info]},
            %Field{name: "title", kind: :string, values: ["AOS confirmed"]},
            %Field{name: "source_record_id", kind: :string, values: ["mission-event-1"]}
          ],
          meta: %{
            family: :mission_timeline,
            links: [
              %DataLink{
                link_id: "mission-event:mission-event-1",
                target: :mission_event,
                target_id: "mission-event-1",
                label: "Mission event"
              }
            ]
          }
        },
        %Frame{
          source: :events,
          shape: :intervals,
          fields: [
            %Field{name: "starts_at", kind: :time, values: [~U[2026-06-17 12:00:00Z]]},
            %Field{name: "ends_at", kind: :time, values: [~U[2026-06-17 12:10:00Z]]},
            %Field{name: "kind", kind: :enum, values: [:scheduled]},
            %Field{name: "status", kind: :enum, values: [:active]},
            %Field{name: "label", kind: :string, values: ["DSS-14 contact"]},
            %Field{name: "contact_id", kind: :string, values: ["contact-1"]},
            %Field{
              name: "source_event_id",
              kind: :string,
              values: ["operational-event-contact-1"]
            }
          ],
          meta: %{
            family: :contacts,
            links: [
              %DataLink{
                link_id: "contact:contact-1",
                target: :contact,
                target_id: "contact-1",
                label: "Contact"
              },
              %DataLink{
                link_id: "operational-event:operational-event-contact-1",
                target: :operational_event,
                target_id: "operational-event-contact-1",
                label: "Operational event"
              }
            ]
          }
        }
      ]
    }

    assert [
             %{
               category: :contacts,
               title: "DSS-14 contact",
               occurred_at: ~U[2026-06-17 12:00:00Z],
               starts_at: ~U[2026-06-17 12:00:00Z],
               ends_at: ~U[2026-06-17 12:10:00Z],
               source_record_id: "contact-1",
               target: :contact,
               target_id: "contact-1",
               links: [
                 %{target: :contact, target_id: "contact-1"},
                 %{target: :operational_event, target_id: "operational-event-contact-1"}
               ]
             },
             %{
               category: :mission_timeline,
               kind: :operator_note,
               severity: :info,
               title: "AOS confirmed",
               occurred_at: ~U[2026-06-17 12:05:00Z],
               source_record_id: "mission-event-1",
               links: [%{target: :mission_event, target_id: "mission-event-1"}]
             }
           ] = EventTimelineData.rows(placement_frames)
  end

  test "stale? reflects event frame freshness warnings" do
    placement_frames = %PlacementFrames{
      primary: [
        %Frame{
          source: :events,
          shape: :events,
          fields: [],
          meta: %{warning_codes: [:source_degraded]}
        }
      ]
    }

    assert EventTimelineData.stale?(placement_frames)
  end

  test "rows attach data-management workflow badges for backfill and revision events" do
    placement_frames = %PlacementFrames{
      primary: [
        %Frame{
          source: :events,
          shape: :events,
          fields: [
            %Field{name: "occurred_at", kind: :time, values: [~U[2026-06-17 12:05:00Z]]},
            %Field{name: "category", kind: :enum, values: [:telemetry_backfill]},
            %Field{name: "kind", kind: :enum, values: [:backfill_started]},
            %Field{name: "severity", kind: :enum, values: [:info]},
            %Field{name: "title", kind: :string, values: ["HK.counter backfill started"]},
            %Field{name: "source_record_id", kind: :string, values: ["backfill-event-1"]},
            %Field{name: "backfill_run_id", kind: :string, values: ["backfill-run-1"]},
            %Field{name: "workflow_run_id", kind: :string, values: ["backfill-run-1"]},
            %Field{name: "workflow_job_id", kind: :string, values: ["job-1"]},
            %Field{name: "workflow_job_status", kind: :enum, values: [:failed]},
            %Field{
              name: "workflow_job_failure",
              kind: :string,
              values: ["dispatcher unavailable"]
            }
          ],
          meta: %{family: :telemetry_backfill}
        },
        %Frame{
          source: :events,
          shape: :events,
          fields: [
            %Field{name: "occurred_at", kind: :time, values: [~U[2026-06-17 12:06:00Z]]},
            %Field{name: "category", kind: :enum, values: [:telemetry_revision]},
            %Field{name: "kind", kind: :enum, values: [:mark_conflict]},
            %Field{name: "severity", kind: :enum, values: [:warning]},
            %Field{name: "title", kind: :string, values: ["HK.counter revision conflict"]},
            %Field{name: "source_record_id", kind: :string, values: ["revision-event-1"]}
          ],
          meta: %{family: :telemetry_revision}
        }
      ]
    }

    assert [
             %{
               backfill_run_id: "backfill-run-1",
               workflow_run_id: "backfill-run-1",
               workflow_job_id: "job-1",
               workflow_job_status: :failed,
               workflow_job_failure: "dispatcher unavailable",
               data_management: %{
                 badges: [
                   %{
                     value: "backfill_started_dispatch_degraded",
                     status: :warning,
                     workflow_job_status: "failed"
                   }
                 ]
               }
             },
             %{data_management: %{badges: [%{value: "correction_conflict"}]}}
           ] = EventTimelineData.rows(placement_frames)
  end

  test "rows preserve source watermark cursor details as audit context" do
    placement_frames = %PlacementFrames{
      primary: [
        %Frame{
          source: :events,
          shape: :events,
          fields: [
            %Field{name: "occurred_at", kind: :time, values: [~U[2026-06-17 12:05:00Z]]},
            %Field{name: "category", kind: :enum, values: [:source_watermark]},
            %Field{name: "kind", kind: :enum, values: [:advanced]},
            %Field{name: "severity", kind: :enum, values: [:info]},
            %Field{name: "title", kind: :string, values: ["telemetry watermark advanced"]},
            %Field{name: "source_record_id", kind: :string, values: ["watermark-event-1"]},
            %Field{name: "logical_source", kind: :enum, values: [:telemetry]},
            %Field{name: "data_source_id", kind: :string, values: ["questdb-flight"]},
            %Field{name: "source_binding_id", kind: :string, values: ["binding-flight"]},
            %Field{name: "realm", kind: :enum, values: [:flight]},
            %Field{name: "dataset", kind: :string, values: ["samples"]},
            %Field{
              name: "complete_through",
              kind: :time,
              values: [~U[2026-06-17 12:04:00Z]]
            },
            %Field{
              name: "latest_receipt_time",
              kind: :time,
              values: [~U[2026-06-17 12:04:30Z]]
            },
            %Field{name: "confidence", kind: :enum, values: [:best_effort]},
            %Field{name: "reason", kind: :enum, values: [:source_watermark_observed]}
          ],
          meta: %{
            family: :source_watermark,
            links: [
              %DataLink{
                link_id: "source-watermark:watermark-event-1",
                target: :source_watermark_event,
                target_id: "watermark-event-1",
                label: "Watermark event"
              }
            ]
          }
        }
      ]
    }

    assert [
             %{
               category: :source_watermark,
               kind: :advanced,
               source_record_id: "watermark-event-1",
               target: :source_watermark_event,
               target_id: "watermark-event-1",
               complete_through: ~U[2026-06-17 12:04:00Z],
               latest_receipt_time: ~U[2026-06-17 12:04:30Z],
               confidence: :best_effort,
               reason: :source_watermark_observed,
               data_management: %{badges: [%{value: "advanced"}]},
               links: [%{target: :source_watermark_event, target_id: "watermark-event-1"}]
             }
           ] = EventTimelineData.rows(placement_frames)
  end
end
