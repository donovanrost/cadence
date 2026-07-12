defmodule CadenceWeb.OpsDashboardShowLive.ComparisonRollupHandoffComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.ComparisonRollupComponents

  test "comparison rollup strip exposes decision, finding, and sample handoff attrs" do
    html =
      render_component(&ComparisonRollupComponents.comparison_rollup_strip/1,
        rollup: rollup()
      )

    document = LazyHTML.from_fragment(html)

    assert ["decision-event-1"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-decision-link="placement-1"]))
             |> LazyHTML.attribute("phx-value-target-id")

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

    assert ["transport"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-decision-link="placement-1"]))
             |> LazyHTML.attribute("phx-value-scope-kind")

    assert ["transport-alpha"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-decision-link="placement-1"]))
             |> LazyHTML.attribute("phx-value-scope-id")

    assert ["transport-alpha,transport-beta"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-decision-link="placement-1"]))
             |> LazyHTML.attribute("phx-value-scope-ids")

    assert ["contact-alpha,contact-beta"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-decision-link="placement-1"]))
             |> LazyHTML.attribute("phx-value-contact-ids")

    assert ["endpoint-alpha"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-decision-link="placement-1"]))
             |> LazyHTML.attribute("phx-value-source-endpoint-id")

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

    assert ["transport-alpha,transport-beta"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-handoff="placement-1"]))
             |> LazyHTML.attribute("phx-value-scope-ids")

    assert ["contact-alpha,contact-beta"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-handoff="placement-1"]))
             |> LazyHTML.attribute("phx-value-contact-ids")

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
  end

  defp rollup do
    %{
      visible?: true,
      widget_count: 1,
      delta_count: 1,
      unchanged_count: 0,
      coverage_count: 0,
      missing_count: 0,
      handled_count: 1,
      open_count: 0,
      unhandled_count: 0,
      states: "increased",
      groups: [
        %{
          key: "deltas",
          label: "Deltas",
          count: 1,
          handled_count: 1,
          unhandled_count: 0,
          placement_ids: "placement-1",
          items: [rollup_item()]
        }
      ]
    }
  end

  defp rollup_item do
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
