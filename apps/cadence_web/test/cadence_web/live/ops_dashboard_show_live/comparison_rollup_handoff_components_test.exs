defmodule CadenceWeb.OpsDashboardShowLive.ComparisonRollupHandoffComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.ComparisonRollupComponents

  test "comparison rollup strip exposes decision, finding, and sample handoff attrs" do
    html =
      render_component(&ComparisonRollupComponents.comparison_rollup_strip/1,
        rollup: rollup()
      )

    vue = LiveVue.Test.get_vue(html, id: "dashboard-comparison-rollup-component")

    [group] = vue.props["presentation"]["rollup"]["details"]["body"]["groups"]
    [item] = group["items"]

    decision =
      Enum.find(item["actions"], fn action ->
        action["attrs"]["data-dashboard-comparison-rollup-decision-link"] == "placement-1"
      end)

    decision_attrs = decision["attrs"]

    assert decision_attrs["phx-value-target-id"] == "decision-event-1"
    assert decision_attrs["phx-value-realm"] == "flight"
    assert decision_attrs["phx-value-data-view"] == "all_revisions"
    assert decision_attrs["phx-value-data-source-id"] == "questdb-flight"
    assert decision_attrs["phx-value-source-binding-id"] == "binding-flight"
    assert decision_attrs["phx-value-time-mode"] == "archive"
    assert decision_attrs["phx-value-time-axis"] == "receipt_time"
    assert decision_attrs["phx-value-replay-run-id"] == "replay-run-1"
    assert decision_attrs["phx-value-scope-kind"] == "transport"
    assert decision_attrs["phx-value-scope-id"] == "transport-alpha"
    assert decision_attrs["phx-value-scope-ids"] == "transport-alpha,transport-beta"
    assert decision_attrs["phx-value-contact-ids"] == "contact-alpha,contact-beta"
    assert decision_attrs["phx-value-source-endpoint-id"] == "endpoint-alpha"

    handoff =
      Enum.find(item["actions"], fn action ->
        action["attrs"]["data-dashboard-comparison-rollup-handoff"] == "placement-1"
      end)

    handoff_attrs = handoff["attrs"]

    assert handoff_attrs["data-dashboard-comparison-rollup-handoff"] == "placement-1"
    assert handoff_attrs["phx-value-target"] == "comparison_finding"
    assert handoff_attrs["phx-value-primary-data-management"] == "recomputed_analysis"
    assert handoff_attrs["phx-value-compare-data-management"] == "degraded"
    assert handoff_attrs["phx-value-scope-kind"] == "transport"
    assert handoff_attrs["phx-value-scope-id"] == "transport-alpha"
    assert handoff_attrs["phx-value-scope-ids"] == "transport-alpha,transport-beta"
    assert handoff_attrs["phx-value-contact-ids"] == "contact-alpha,contact-beta"
    assert handoff_attrs["phx-value-source-endpoint-id"] == "endpoint-alpha"
    assert handoff_attrs["phx-value-widget-type"] == "status_matrix"
    assert handoff_attrs["phx-value-widget-source"] == "operational_observables"
    assert handoff_attrs["phx-value-primary-kind"] == "status_matrix"
    assert handoff_attrs["phx-value-compare-kind"] == "status_matrix"

    assert handoff_attrs["phx-value-primary-observables"] ==
             "comms.transport.connection_state:transport-alpha"

    assert handoff_attrs["phx-value-compare-observables"] ==
             "comms.transport.connection_state:transport-alpha"

    sample_actions =
      Enum.filter(
        item["actions"],
        &Map.has_key?(&1["attrs"], "data-dashboard-comparison-rollup-link")
      )

    assert Enum.map(sample_actions, & &1["attrs"]["data-dashboard-comparison-rollup-link"]) ==
             ["primary", "compare"]

    [primary, compare] = sample_actions
    assert primary["attrs"]["phx-value-realm"] == "flight"
    assert compare["attrs"]["phx-value-data-source-id"] == "questdb-sim"
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))
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
