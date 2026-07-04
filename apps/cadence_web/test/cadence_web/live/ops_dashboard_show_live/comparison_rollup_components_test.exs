defmodule CadenceWeb.OpsDashboardShowLive.ComparisonRollupComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Cadence.Dashboards.InvestigationPreset
  alias CadenceWeb.OpsDashboardShowLive.ComparisonRollupComponents

  test "comparison rollup strip exposes findings, handoffs, and saved presets" do
    html =
      render_component(&ComparisonRollupComponents.comparison_rollup_strip/1,
        rollup: rollup(),
        preset: preset(),
        saved_presets: [saved_preset()]
      )

    document = LazyHTML.from_fragment(html)

    assert ["4"] =
             document
             |> LazyHTML.query("#dashboard-comparison-rollup")
             |> LazyHTML.attribute("data-dashboard-comparison-widgets")

    assert ["1"] =
             document
             |> LazyHTML.query("#dashboard-comparison-rollup")
             |> LazyHTML.attribute("data-dashboard-comparison-open")

    assert ["placement-2"] =
             document
             |> LazyHTML.query("#dashboard-comparison-rollup")
             |> LazyHTML.attribute("data-dashboard-comparison-open-placements")

    assert ["open", "handled"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-workflow-badge]")
             |> LazyHTML.attribute("data-dashboard-comparison-workflow-badge")

    assert ["deltas", "missing"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-rollup-group]")
             |> LazyHTML.attribute("data-dashboard-comparison-rollup-group")

    assert ["placement-1", "placement-2"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-rollup-item]")
             |> LazyHTML.attribute("data-dashboard-comparison-rollup-item")

    assert ["applied"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-item="placement-1"]))
             |> LazyHTML.attribute("data-dashboard-comparison-rollup-decision-status")

    assert ["decision-event-1"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-decision-link="placement-1"]))
             |> LazyHTML.attribute("phx-value-target-id")

    assert ["recomputed_analysis"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-item="placement-1"]))
             |> LazyHTML.attribute("data-dashboard-comparison-rollup-primary-data-management")

    assert ["status_matrix"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-item="placement-1"]))
             |> LazyHTML.attribute("data-dashboard-comparison-rollup-widget-type")

    assert ["operational_observables"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-item="placement-1"]))
             |> LazyHTML.attribute("data-dashboard-comparison-rollup-widget-source")

    assert ["status_matrix"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-item="placement-1"]))
             |> LazyHTML.attribute("data-dashboard-comparison-rollup-primary-kind")

    assert ["status_matrix"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-item="placement-1"]))
             |> LazyHTML.attribute("data-dashboard-comparison-rollup-compare-kind")

    assert ["comms.transport.connection_state:transport-alpha"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-item="placement-1"]))
             |> LazyHTML.attribute("data-dashboard-comparison-rollup-primary-observables")

    assert ["comms.transport.connection_state:transport-alpha"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-item="placement-1"]))
             |> LazyHTML.attribute("data-dashboard-comparison-rollup-compare-observables")

    assert ["degraded"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-item="placement-1"]))
             |> LazyHTML.attribute("data-dashboard-comparison-rollup-compare-data-management")

    assert ["transport"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-item="placement-1"]))
             |> LazyHTML.attribute("data-dashboard-comparison-rollup-scope-kind")

    assert ["transport-alpha"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-item="placement-1"]))
             |> LazyHTML.attribute("data-dashboard-comparison-rollup-scope-id")

    assert ["endpoint-alpha"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-item="placement-1"]))
             |> LazyHTML.attribute("data-dashboard-comparison-rollup-source-endpoint-id")

    assert ["flight"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-decision-link="placement-1"]))
             |> LazyHTML.attribute("phx-value-realm")

    assert ["all_revisions"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-decision-link="placement-1"]))
             |> LazyHTML.attribute("phx-value-data-view")

    assert ["questdb-flight"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-decision-link="placement-1"]))
             |> LazyHTML.attribute("phx-value-data-source-id")

    assert ["binding-flight"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-decision-link="placement-1"]))
             |> LazyHTML.attribute("phx-value-source-binding-id")

    assert ["archive"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-decision-link="placement-1"]))
             |> LazyHTML.attribute("phx-value-time-mode")

    assert ["receipt_time"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-decision-link="placement-1"]))
             |> LazyHTML.attribute("phx-value-time-axis")

    assert ["replay-run-1"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-decision-link="placement-1"]))
             |> LazyHTML.attribute("phx-value-replay-run-id")

    assert ["placement-1"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-handoff="placement-1"]))
             |> LazyHTML.attribute("data-dashboard-comparison-rollup-handoff")

    assert ["comparison_finding"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-handoff="placement-1"]))
             |> LazyHTML.attribute("phx-value-target")

    assert ["recomputed_analysis"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-handoff="placement-1"]))
             |> LazyHTML.attribute("phx-value-primary-data-management")

    assert ["degraded"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-handoff="placement-1"]))
             |> LazyHTML.attribute("phx-value-compare-data-management")

    assert ["transport"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-handoff="placement-1"]))
             |> LazyHTML.attribute("phx-value-scope-kind")

    assert ["transport-alpha"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-handoff="placement-1"]))
             |> LazyHTML.attribute("phx-value-scope-id")

    assert ["endpoint-alpha"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-handoff="placement-1"]))
             |> LazyHTML.attribute("phx-value-source-endpoint-id")

    assert ["status_matrix"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-handoff="placement-1"]))
             |> LazyHTML.attribute("phx-value-widget-type")

    assert ["operational_observables"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-handoff="placement-1"]))
             |> LazyHTML.attribute("phx-value-widget-source")

    assert ["status_matrix"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-handoff="placement-1"]))
             |> LazyHTML.attribute("phx-value-primary-kind")

    assert ["status_matrix"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-handoff="placement-1"]))
             |> LazyHTML.attribute("phx-value-compare-kind")

    assert ["comms.transport.connection_state:transport-alpha"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-handoff="placement-1"]))
             |> LazyHTML.attribute("phx-value-primary-observables")

    assert ["comms.transport.connection_state:transport-alpha"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-handoff="placement-1"]))
             |> LazyHTML.attribute("phx-value-compare-observables")

    assert ["primary", "compare"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-rollup-link]")
             |> LazyHTML.attribute("data-dashboard-comparison-rollup-link")

    assert ["flight"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-link="primary"]))
             |> LazyHTML.attribute("phx-value-realm")

    assert ["questdb-sim"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-link="compare"]))
             |> LazyHTML.attribute("phx-value-data-source-id")

    assert [encoded_open_findings] =
             document
             |> LazyHTML.query("#dashboard-comparison-rollup")
             |> LazyHTML.attribute("data-dashboard-comparison-open-findings")

    decoded_open_findings = Jason.decode!(encoded_open_findings)

    assert %{
             "schema" => "dashboard_comparison_open_findings.v1",
             "workflow_intent" => %{
               "schema" => "dashboard_comparison_workflow_intent.v1",
               "kind" => "bulk_correction_authority_review",
               "source" => "dashboard_comparison_rollup",
               "action" => "request_comparison_review",
               "selection_kind" => "open_comparison_findings",
               "selection_count" => 1,
               "placement_ids" => ["placement-2"],
               "primary_data_view" => "all_revisions",
               "compare_data_view" => "canonical"
             },
             "comparison" => %{"open_count" => 1, "open_placement_ids" => ["placement-2"]}
           } = decoded_open_findings

    assert [
             %{
               "placement_id" => "placement-2",
               "widget_type" => "data_table",
               "widget_source" => "operational_observables",
               "primary_kind" => "data_table",
               "compare_kind" => "data_table",
               "primary_observable_ids" => ["ingress.processing_latency_ms:endpoint-beta"],
               "compare_observable_ids" => ["ingress.processing_latency_ms:endpoint-beta"],
               "observation_identity_id" => "identity-primary-2",
               "primary_observation_identity_id" => "identity-primary-2",
               "compare_observation_identity_id" => "identity-compare-2",
               "primary_observation_id" => "observation-primary-2",
               "compare_observation_id" => "observation-compare-2",
               "primary_revision" => 3,
               "compare_revision" => 2,
               "selection_query" => selection_query,
               "selection_path" => selection_path
             }
           ] = decoded_open_findings["findings"]

    assert selection_query == %{
             "panel" => "data_link",
             "selected_target" => "comparison_finding",
             "selected_id" => "placement-2",
             "selected_placement" => "placement-2",
             "selected_widget" => "widget-2",
             "selected_widget_title" => "Current",
             "selected_widget_type" => "data_table",
             "selected_widget_source" => "operational_observables",
             "selected_primary_kind" => "data_table",
             "selected_compare_kind" => "data_table",
             "selected_primary_observables" => "ingress.processing_latency_ms:endpoint-beta",
             "selected_compare_observables" => "ingress.processing_latency_ms:endpoint-beta",
             "selected_comparison_state" => "missing",
             "selected_comparison_delta" => "-1",
             "selected_primary_sample" => "primary-sample-2",
             "selected_compare_sample" => "compare-sample-2",
             "selected_observation_identity" => "identity-primary-2",
             "selected_primary_observation_identity" => "identity-primary-2",
             "selected_compare_observation_identity" => "identity-compare-2",
             "selected_primary_observation" => "observation-primary-2",
             "selected_compare_observation" => "observation-compare-2",
             "selected_primary_revision" => 3,
             "selected_compare_revision" => 2,
             "selected_primary_data_view" => "all_revisions",
             "selected_compare_data_view" => "canonical",
             "selected_primary_data_management" => "late_data_accepted",
             "selected_compare_data_management" => "canonical",
             "selected_primary_count" => 2,
             "selected_compare_count" => 1,
             "selected_scope_kind" => "source_endpoint",
             "selected_scope_id" => "endpoint-beta",
             "selected_resource_id" => "endpoint-beta",
             "selected_source_endpoint_id" => "endpoint-beta",
             "selected_ground_station_id" => "dss-15"
           }

    assert selection_path =~ "/missions/mission-1/ops/dashboards/dashboard-1?"
    assert selection_path =~ "data_view=all_revisions"
    assert selection_path =~ "compare_data_view=canonical"
    assert selection_path =~ "panel=data_link"
    assert selection_path =~ "selected_target=comparison_finding"
    assert selection_path =~ "selected_id=placement-2"
    assert selection_path =~ "selected_widget_type=data_table"
    assert selection_path =~ "selected_widget_source=operational_observables"
    assert selection_path =~ "selected_primary_kind=data_table"
    assert selection_path =~ "selected_compare_kind=data_table"
    assert selection_path =~ "selected_primary_observables="
    assert selection_path =~ "selected_observation_identity=identity-primary-2"
    assert selection_path =~ "selected_primary_data_management=late_data_accepted"
    assert selection_path =~ "selected_compare_data_management=canonical"
    assert selection_path =~ "selected_scope_kind=source_endpoint"
    assert selection_path =~ "selected_source_endpoint_id=endpoint-beta"

    assert [^encoded_open_findings] =
             document
             |> LazyHTML.query("#dashboard-comparison-open-findings-copy")
             |> LazyHTML.attribute("data-clipboard-text")

    assert ["request_comparison_review"] =
             document
             |> LazyHTML.query("#dashboard-comparison-open-findings-review-form")
             |> LazyHTML.attribute("phx-submit")

    assert ["available"] =
             document
             |> LazyHTML.query("#dashboard-comparison-open-findings-review")
             |> LazyHTML.attribute("data-dashboard-comparison-open-findings-review-state")

    assert ["preset-1"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-saved-preset-apply]")
             |> LazyHTML.attribute("phx-value-preset-id")
  end

  test "comparison rollup strip disables duplicate open review requests" do
    html =
      render_component(&ComparisonRollupComponents.comparison_rollup_strip/1,
        rollup: rollup(),
        preset: preset(),
        open_review_summary: %{
          placement_ids: ["placement-2"],
          request_ids: ["dashboard-lifecycle-event-review"]
        }
      )

    document = LazyHTML.from_fragment(html)

    assert ["requested"] =
             document
             |> LazyHTML.query("#dashboard-comparison-rollup")
             |> LazyHTML.attribute("data-dashboard-comparison-open-findings-review-state")

    assert ["dashboard-lifecycle-event-review"] =
             document
             |> LazyHTML.query("#dashboard-comparison-rollup")
             |> LazyHTML.attribute("data-dashboard-comparison-open-findings-review-request-ids")

    assert ["requested"] =
             document
             |> LazyHTML.query("#dashboard-comparison-open-findings-review")
             |> LazyHTML.attribute("data-dashboard-comparison-open-findings-review-state")

    assert ["Comparison review already requested"] =
             document
             |> LazyHTML.query("#dashboard-comparison-open-findings-review")
             |> LazyHTML.attribute("title")

    assert [""] =
             document
             |> LazyHTML.query("#dashboard-comparison-open-findings-review")
             |> LazyHTML.attribute("disabled")
  end

  test "comparison rollup strip is hidden when no comparison is active" do
    html =
      render_component(&ComparisonRollupComponents.comparison_rollup_strip/1,
        rollup: %{
          visible?: false,
          widget_count: 0,
          delta_count: 0,
          unchanged_count: 0,
          coverage_count: 0,
          missing_count: 0,
          states: ""
        }
      )

    assert [] =
             html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("#dashboard-comparison-rollup")
             |> LazyHTML.attribute("id")
  end

  defp rollup do
    %{
      visible?: true,
      widget_count: 4,
      delta_count: 1,
      unchanged_count: 1,
      coverage_count: 1,
      missing_count: 1,
      handled_count: 1,
      open_count: 1,
      unhandled_count: 1,
      states: "increased,unchanged,available,missing",
      workflow_groups: [
        %{
          key: "open",
          label: "Open findings",
          count: 1,
          placement_ids: "placement-2",
          items: [
            %{
              placement_id: "placement-2",
              widget_id: "widget-2",
              title: "Current",
              state: "missing",
              label: "No compare data",
              decision_status: "unhandled"
            }
          ]
        },
        %{
          key: "handled",
          label: "Handled findings",
          count: 1,
          placement_ids: "placement-1",
          items: [
            %{
              placement_id: "placement-1",
              widget_id: "widget-1",
              title: "Voltage",
              state: "increased",
              label: "Canonical +2",
              decision_status: "applied",
              decision_event_id: "decision-event-1"
            }
          ]
        }
      ],
      groups: [
        %{
          key: "deltas",
          label: "Deltas",
          count: 1,
          handled_count: 1,
          unhandled_count: 0,
          placement_ids: "placement-1",
          items: [
            %{
              placement_id: "placement-1",
              widget_id: "widget-1",
              title: "Voltage",
              state: "increased",
              label: "Canonical +2",
              widget_type: "status_matrix",
              widget_source: "operational_observables",
              primary_kind: "status_matrix",
              compare_kind: "status_matrix",
              primary_observable_ids: ["comms.transport.connection_state:transport-alpha"],
              compare_observable_ids: ["comms.transport.connection_state:transport-alpha"],
              primary_view: "all_revisions",
              compare_view: "canonical",
              primary_count: 1,
              compare_count: 1,
              delta: "+2",
              decision_status: "applied",
              decision_event_id: "decision-event-1",
              decision: "mark_conflict",
              decision_reason: "operator_confirmed_comparison",
              primary_sample_id: "primary-sample-1",
              compare_sample_id: "compare-sample-1",
              scope_kind: "transport",
              scope_id: "transport-alpha",
              resource_id: "transport-alpha",
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              scope_link_id: "link-alpha",
              primary_data_management: data_management("recomputed_analysis"),
              compare_data_management: data_management("degraded"),
              primary_data_link: presented_link(),
              compare_data_link: %{
                presented_link()
                | link_id: "compare-link-1",
                  target_id: "compare-sample-1",
                  context: %{
                    data: %{
                      realm: :simulation,
                      view: "canonical",
                      data_source_id: "questdb-sim",
                      source_binding_id: "binding-sim"
                    },
                    time: %{mode: "replay_run", axis: "generation_time"}
                  }
              }
            }
          ]
        },
        %{
          key: "missing",
          label: "Missing compare data",
          count: 1,
          placement_ids: "placement-2",
          items: [
            %{
              placement_id: "placement-2",
              widget_id: "widget-2",
              title: "Current",
              state: "missing",
              label: "No compare data"
            }
          ]
        }
      ]
    }
  end

  defp preset do
    %{
      "schema" => "dashboard_comparison_investigation_preset.v1",
      "dashboard_id" => "dashboard-1",
      "current_path" =>
        "/missions/mission-1/ops/dashboards/dashboard-1?data_view=all_revisions&compare_data_view=canonical",
      "comparison" => %{
        "primary_data_view" => "all_revisions",
        "compare_data_view" => "canonical",
        "delta_count" => 1,
        "open_count" => 1
      },
      "runtime_query" => %{
        "data_view" => "all_revisions",
        "compare_data_view" => "canonical"
      },
      "workflow_groups" => [
        %{
          "key" => "open",
          "label" => "Open findings",
          "count" => 1,
          "placement_ids" => ["placement-2"],
          "items" => [
            %{
              "placement_id" => "placement-2",
              "widget_id" => "widget-2",
              "title" => "Current",
              "state" => "missing",
              "label" => "No compare data",
              "widget_type" => "data_table",
              "widget_source" => "operational_observables",
              "primary_kind" => "data_table",
              "compare_kind" => "data_table",
              "primary_observable_ids" => ["ingress.processing_latency_ms:endpoint-beta"],
              "compare_observable_ids" => ["ingress.processing_latency_ms:endpoint-beta"],
              "delta" => "-1",
              "primary_count" => 2,
              "compare_count" => 1,
              "primary_sample_id" => "primary-sample-2",
              "compare_sample_id" => "compare-sample-2",
              "observation_identity_id" => "identity-primary-2",
              "primary_observation_identity_id" => "identity-primary-2",
              "compare_observation_identity_id" => "identity-compare-2",
              "primary_observation_id" => "observation-primary-2",
              "compare_observation_id" => "observation-compare-2",
              "primary_revision" => 3,
              "compare_revision" => 2,
              "primary_data_view" => "all_revisions",
              "compare_data_view" => "canonical",
              "scope_kind" => "source_endpoint",
              "scope_id" => "endpoint-beta",
              "resource_id" => "endpoint-beta",
              "source_endpoint_id" => "endpoint-beta",
              "ground_station_id" => "dss-15",
              "primary_data_management" => data_management("late_data_accepted"),
              "compare_data_management" => data_management("canonical"),
              "decision_status" => "unhandled"
            }
          ]
        }
      ]
    }
  end

  defp saved_preset do
    InvestigationPreset.new(%{
      dashboard_investigation_preset_id: "preset-1",
      mission_id: "mission-1",
      dashboard_id: "dashboard-1",
      name: "All revisions vs canonical",
      schema: "dashboard_comparison_investigation_preset.v1",
      preset_kind: :comparison,
      runtime_query: %{
        "data_view" => "all_revisions",
        "compare_data_view" => "canonical"
      },
      primary_data_view: "all_revisions",
      compare_data_view: "canonical",
      affected_placement_ids: ["placement-1"]
    })
  end

  defp presented_link do
    %{
      link_id: "link-1",
      label: "Telemetry sample",
      target_text: "telemetry sample",
      target_id: "sample-1",
      context: %{
        data: %{
          realm: :flight,
          view: "canonical",
          data_source_id: "questdb-flight",
          source_binding_id: "binding-flight",
          replay_run_id: "replay-run-1"
        },
        time: %{
          mode: "archive",
          axis: "receipt_time"
        }
      }
    }
  end

  defp data_management(value) do
    %{
      badges: [
        %{
          kind: :data_management,
          value: value,
          label: value,
          status: :info,
          code: value
        }
      ]
    }
  end
end
