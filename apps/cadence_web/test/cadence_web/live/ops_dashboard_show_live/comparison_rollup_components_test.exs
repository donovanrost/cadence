defmodule CadenceWeb.OpsDashboardShowLive.ComparisonRollupComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.ComparisonRollupComponents

  test "comparison rollup strip exposes summary groups and item metadata" do
    html =
      render_component(&ComparisonRollupComponents.comparison_rollup_strip/1,
        rollup: rollup()
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

    assert ["transport-alpha,transport-beta"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-item="placement-1"]))
             |> LazyHTML.attribute("data-dashboard-comparison-rollup-scope-ids")

    assert ["contact-alpha,contact-beta"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-item="placement-1"]))
             |> LazyHTML.attribute("data-dashboard-comparison-rollup-contact-ids")

    assert ["endpoint-alpha"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-item="placement-1"]))
             |> LazyHTML.attribute("data-dashboard-comparison-rollup-source-endpoint-id")
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
