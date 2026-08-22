defmodule CadenceWeb.OpsDashboardShowLive.DataLinkPresentationTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.DataLink
  alias CadenceWeb.OpsDashboardShowLive.DataLinkPresentation

  test "related presents data-link rows with direct context" do
    link = %DataLink{
      link_id: "telemetry_sample:sample-1:request-1",
      label: "Sample",
      target: :telemetry_sample,
      target_id: "sample-1",
      relationship_kind: :evidence,
      context: %{
        data: %{
          realm: "flight",
          view: "raw",
          data_source_id: "questdb-flight",
          source_binding_id: "binding-flight",
          replay_run_id: "replay-1"
        },
        time: %{
          mode: "archive",
          axis: "receipt_time"
        }
      }
    }

    assert [row] = DataLinkPresentation.related([link])

    assert %{
             link: ^link,
             link_id: "telemetry_sample:sample-1:request-1",
             target: "telemetry_sample",
             target_text: "telemetry sample",
             target_id: "sample-1",
             label: "Sample",
             relationship_kind: :evidence,
             realm: "flight",
             data_view: "raw",
             data_source_id: "questdb-flight",
             source_binding_id: "binding-flight",
             time_mode: "archive",
             time_axis: "receipt_time",
             replay_run_id: "replay-1"
           } = row
  end

  test "related normalizes serialized relationship kinds" do
    assert [
             %{relationship_kind: :correction_request},
             %{relationship_kind: :comparison_review_origin}
           ] =
             DataLinkPresentation.related([
               %{
                 "label" => "Corrected by request",
                 "target" => "telemetry_backfill_lifecycle_event",
                 "target_id" => "event-1",
                 "relationship_kind" => "correction-request"
               },
               %{
                 "label" => "Comparison review request",
                 "target" => "dashboard_lifecycle_event",
                 "target_id" => "review-request-1",
                 "relationship_kind" => "comparison-review-origin"
               }
             ])
  end

  test "related groups links by operator navigation semantics" do
    links = [
      link(:telemetry_sample, "sample-1", "Telemetry sample", :evidence),
      link(
        :telemetry_backfill_lifecycle_event,
        "retry-event-1",
        "Retry event HK.counter",
        :retry_event
      ),
      link(
        :telemetry_backfill_lifecycle_event,
        "source-event-1",
        "Source event HK.counter",
        :source_event
      ),
      link(
        :dashboard_lifecycle_event,
        "review-request-1",
        "Comparison review request",
        :comparison_review_origin
      ),
      link(
        :telemetry_backfill_lifecycle_event,
        "transition-event-1",
        "Correction transition HK.counter",
        :correction_transition
      ),
      link(
        :telemetry_backfill_lifecycle_event,
        "policy-event-1",
        "Late data policy HK.counter",
        :late_data_policy_event
      )
    ]

    assert [
             %{
               key: "source",
               label: "Source",
               order: 0,
               links: [%{target_id: "source-event-1"}, %{target_id: "review-request-1"}]
             },
             %{
               key: "recovery",
               label: "Recovery",
               order: 1,
               links: [%{target_id: "retry-event-1"}, %{target_id: "policy-event-1"}]
             },
             %{
               key: "follow-up",
               label: "Follow-up",
               order: 2,
               links: [%{target_id: "transition-event-1"}]
             },
             %{key: "evidence", label: "Evidence", order: 3, links: [%{target_id: "sample-1"}]}
           ] = DataLinkPresentation.related_groups(links)
  end

  test "related groups legacy unlabeled relationship kinds from link labels" do
    links = [
      %{
        target: :telemetry_backfill_lifecycle_event,
        target_id: "transition-event-1",
        label: "Follow-up event HK.counter"
      },
      %{
        target: :telemetry_backfill_lifecycle_event,
        target_id: "correction-event-1",
        label: "Correction request HK.counter"
      },
      %{
        target: :telemetry_backfill_lifecycle_event,
        target_id: "source-event-1",
        label: "Retry source event"
      },
      %{target: :telemetry_sample, target_id: "sample-1", label: "Telemetry sample"}
    ]

    assert [
             %{key: "source", links: [%{target_id: "source-event-1"}]},
             %{key: "recovery", links: [%{target_id: "correction-event-1"}]},
             %{key: "follow-up", links: [%{target_id: "transition-event-1"}]},
             %{key: "evidence", links: [%{target_id: "sample-1"}]}
           ] = DataLinkPresentation.related_groups(links)
  end

  test "panel derives selection, navigation, and related-link presentation from inspector" do
    inspector = %{
      status_text: "resolved",
      status: :resolved,
      title: "Backfill lifecycle event",
      target: :telemetry_backfill_lifecycle_event,
      target_text: "telemetry backfill lifecycle event",
      target_id: "source-event-1",
      link_id: "source-link-1",
      link_label: "Backfill lifecycle event",
      source_text: "frame",
      source_context: %{
        realm: "flight",
        data_view: "canonical",
        data_source_id: "questdb-flight",
        source_binding_id: "binding-flight",
        time_mode: "archive",
        time_axis: "receipt_time",
        replay_run_id: "replay-1"
      },
      context_rows: [
        %{label: "Scope", value: "spacecraft:single:sc-1"},
        %{label: "Limit mode", value: "observed"}
      ],
      rows: [
        %{label: "Backfill lifecycle event", value: "source-event-1"},
        %{label: "Event type", value: "backfill_completed"},
        %{label: "Backfill run", value: "run-1"},
        %{label: "Workflow", value: "backfill"},
        %{label: "Realm", value: "flight"},
        %{label: "Data source", value: "questdb-flight"},
        %{label: "Source binding", value: "binding-flight"}
      ],
      navigation: %{
        trail: [
          %{
            link_id: "root-link-1",
            target: "telemetry_backfill_lifecycle_event",
            target_id: "root-event-1",
            relationship_kind: "source_event",
            relationship_label: "Source event HK.counter",
            realm: "flight",
            data_view: "canonical",
            data_source_id: "questdb-flight",
            source_binding_id: "binding-flight",
            time_mode: "archive",
            time_axis: "receipt_time",
            replay_run_id: "replay-1"
          }
        ]
      },
      related_links: [
        link(
          :telemetry_backfill_lifecycle_event,
          "retry-event-1",
          "Retry event HK.counter",
          :retry_event
        )
      ]
    }

    panel = DataLinkPresentation.panel(inspector)

    assert panel.selection_summary == %{
             link_id: "source-link-1",
             status: "resolved",
             target: "telemetry backfill lifecycle event",
             target_id: "source-event-1",
             source: "frame",
             realm: "flight",
             data_view: "canonical",
             data_source_id: "questdb-flight",
             source_binding_id: "binding-flight",
             time_mode: "archive",
             time_axis: "receipt_time",
             replay_run_id: "replay-1",
             scope: "spacecraft:single:sc-1",
             limit_mode: "observed"
           }

    assert %{label: "Data source", value: "questdb-flight"} in panel.selection_summary_rows

    assert [
             %{
               target_id: "root-event-1",
               relationship_kind: "source_event",
               back_link: %{
                 target_id: "root-event-1",
                 realm: "flight",
                 data_view: "canonical",
                 data_source_id: "questdb-flight",
                 source_binding_id: "binding-flight",
                 time_mode: "archive",
                 time_axis: "receipt_time",
                 replay_run_id: "replay-1"
               }
             }
           ] = panel.navigation_trail

    assert [%{key: "recovery", links: [%{target_id: "retry-event-1"}]}] = panel.related_groups
    assert panel.workflow_explanation?
    assert panel.late_data_policy_controls?
    assert panel.historical_workflow_controls?
    refute panel.revision_decision_controls?
  end

  test "panel exposes revision decision control eligibility" do
    panel =
      DataLinkPresentation.panel(%{
        status: :context_only,
        status_text: "context_only",
        target: :comparison_finding,
        target_text: "comparison finding",
        target_id: "placement-1",
        rows: [
          %{label: "Observation identity", value: "identity-1"},
          %{label: "Realm", value: "flight"},
          %{label: "Data source", value: "questdb-flight"},
          %{label: "Source binding", value: "binding-flight"}
        ]
      })

    assert panel.revision_decision_controls?
    refute panel.workflow_explanation?
    refute panel.late_data_policy_controls?
    refute panel.historical_workflow_controls?
  end

  test "related handles unsupported links with stable defaults" do
    assert [
             %{
               link_id: nil,
               target: "",
               target_text: "unknown",
               target_id: nil,
               label: "unknown"
             }
           ] = DataLinkPresentation.related([%{}])
  end

  defp link(target, target_id, label, relationship_kind) do
    %DataLink{
      link_id: "#{target}:#{target_id}:request-1",
      target: target,
      target_id: target_id,
      label: label,
      relationship_kind: relationship_kind
    }
  end
end
