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
    assert [%{relationship_kind: :correction_request}] =
             DataLinkPresentation.related([
               %{
                 "label" => "Corrected by request",
                 "target" => "telemetry_backfill_lifecycle_event",
                 "target_id" => "event-1",
                 "relationship_kind" => "correction-request"
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
             %{key: "source", label: "Source", order: 0, links: [%{target_id: "source-event-1"}]},
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

  test "navigation event attrs append the current inspector to the bounded trail" do
    inspector = %{
      title: "Backfill lifecycle event",
      target: :telemetry_backfill_lifecycle_event,
      target_id: "source-event-1",
      link_id: "source-link-1",
      source_context: %{
        realm: "flight",
        data_view: "canonical",
        data_source_id: "questdb-flight",
        source_binding_id: "binding-flight",
        time_mode: "archive",
        time_axis: "receipt_time",
        replay_run_id: "replay-1"
      },
      navigation: %{
        trail: [
          %{
            target: "telemetry_backfill_lifecycle_event",
            target_id: "root-event-1",
            relationship_kind: "source_event",
            realm: "flight",
            data_view: "canonical",
            data_source_id: "questdb-flight",
            source_binding_id: "binding-flight",
            time_mode: "archive",
            time_axis: "receipt_time",
            replay_run_id: "replay-1"
          }
        ]
      }
    }

    related_link =
      link(
        :telemetry_backfill_lifecycle_event,
        "retry-event-1",
        "Retry event HK.counter",
        :retry_event
      )

    attrs = DataLinkPresentation.navigation_event_attrs(inspector, related_link)

    assert attrs.nav_from_link_id == "source-link-1"
    assert attrs.nav_from_target == "telemetry_backfill_lifecycle_event"
    assert attrs.nav_from_target_id == "source-event-1"
    assert attrs.nav_from_relationship_kind == "retry_event"

    assert [
             %{"target_id" => "root-event-1"},
             %{
               "target_id" => "source-event-1",
               "relationship_kind" => "retry_event",
               "relationship_label" => "Retry event HK.counter",
               "realm" => "flight",
               "data_view" => "canonical",
               "data_source_id" => "questdb-flight",
               "source_binding_id" => "binding-flight",
               "time_mode" => "archive",
               "time_axis" => "receipt_time",
               "replay_run_id" => "replay-1"
             }
           ] = Jason.decode!(attrs.nav_trail)
  end

  test "navigation event attrs fall back to related link context for trail entries" do
    inspector = %{
      title: "Backfill lifecycle event",
      target: :telemetry_backfill_lifecycle_event,
      target_id: "source-event-1",
      link_id: "source-link-1"
    }

    related_link = %DataLink{
      link_id: "telemetry_backfill_lifecycle_event:retry-event-1:request-1",
      target: :telemetry_backfill_lifecycle_event,
      target_id: "retry-event-1",
      label: "Retry event HK.counter",
      relationship_kind: :retry_event,
      context: %{
        data: %{
          realm: "backfill",
          view: "canonical",
          data_source_id: "managed_questdb_backfill",
          source_binding_id: "backfill_telemetry"
        },
        time: %{mode: "live", axis: "generation_time"}
      }
    }

    attrs = DataLinkPresentation.navigation_event_attrs(inspector, related_link)

    assert [
             %{
               "target_id" => "source-event-1",
               "realm" => "backfill",
               "data_view" => "canonical",
               "data_source_id" => "managed_questdb_backfill",
               "source_binding_id" => "backfill_telemetry",
               "time_mode" => "live",
               "time_axis" => "generation_time"
             }
           ] = Jason.decode!(attrs.nav_trail)
  end

  test "evidence falls back to inspector source context" do
    link = %{
      link_id: "telemetry_point:HK.counter:request-1",
      label: nil,
      target_text: "telemetry point",
      target_id: "HK.counter",
      context: %{}
    }

    inspector = %{
      source_context: %{
        realm: "flight",
        data_view: "derived",
        data_source_id: "questdb-flight",
        source_binding_id: "binding-flight",
        time_mode: "archive",
        time_axis: "receipt_time",
        replay_run_id: "replay-1"
      }
    }

    assert [row] = DataLinkPresentation.evidence([link], inspector)

    assert %{
             link_id: "telemetry_point:HK.counter:request-1",
             target: "",
             target_text: "telemetry point",
             target_id: "HK.counter",
             label: "telemetry point",
             realm: "flight",
             data_view: "derived",
             data_source_id: "questdb-flight",
             source_binding_id: "binding-flight",
             time_mode: "archive",
             time_axis: "receipt_time",
             replay_run_id: "replay-1"
           } = row
  end

  test "evidence link context wins over inspector fallback context" do
    link = %{
      "link_id" => "telemetry_point:HK.counter:request-1",
      "target" => "telemetry_point",
      "target_id" => "HK.counter",
      "context" => %{
        "data" => %{
          "realm" => "simulation",
          "data_source_id" => "questdb-sim"
        },
        "time" => %{
          "mode" => "live"
        }
      }
    }

    inspector = %{
      "source_context" => %{
        "realm" => "flight",
        "data_source_id" => "questdb-flight",
        "time_mode" => "archive"
      }
    }

    assert [row] = DataLinkPresentation.evidence([link], inspector)

    assert row.link_id == "telemetry_point:HK.counter:request-1"
    assert row.target == "telemetry_point"
    assert row.target_text == "telemetry point"
    assert row.target_id == "HK.counter"
    assert row.label == "telemetry point"
    assert row.realm == "simulation"
    assert row.data_source_id == "questdb-sim"
    assert row.time_mode == "live"
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
