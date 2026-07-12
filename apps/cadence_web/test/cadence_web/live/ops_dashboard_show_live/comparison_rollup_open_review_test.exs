defmodule CadenceWeb.OpsDashboardShowLive.ComparisonRollupOpenReviewTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.ComparisonRollupComponents

  test "comparison rollup strip exposes open findings review payload" do
    html =
      render_component(&ComparisonRollupComponents.comparison_rollup_strip/1,
        rollup: rollup(),
        preset: preset()
      )

    document = LazyHTML.from_fragment(html)

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
               "scope_ids" => ["endpoint-alpha", "endpoint-beta"],
               "contact_ids" => ["contact-alpha", "contact-beta"],
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
             "selected_scope_ids" => "endpoint-alpha,endpoint-beta",
             "selected_contact_ids" => "contact-alpha,contact-beta",
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
    assert selection_path =~ "selected_scope_ids=endpoint-alpha%2Cendpoint-beta"
    assert selection_path =~ "selected_contact_ids=contact-alpha%2Ccontact-beta"

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
              scope_ids: ["transport-alpha", "transport-beta"],
              contact_ids: ["contact-alpha", "contact-beta"],
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
              "scope_ids" => ["endpoint-alpha", "endpoint-beta"],
              "contact_ids" => ["contact-alpha", "contact-beta"],
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
