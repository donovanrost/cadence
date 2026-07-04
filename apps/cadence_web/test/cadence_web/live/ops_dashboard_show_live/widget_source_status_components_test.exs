defmodule CadenceWeb.OpsDashboardShowLive.WidgetSourceStatusComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.WidgetSourceStatusComponents

  test "source_status_badge renders actionable evidence and inventory controls" do
    html =
      render_component(&WidgetSourceStatusComponents.source_status_badge/1,
        source_status: source_status(),
        mission_id: "mission-1"
      )

    document = LazyHTML.from_fragment(html)

    assert ["open_evidence"] =
             document
             |> LazyHTML.query(~s(button[data-widget-source-badge="stale"]))
             |> LazyHTML.attribute("phx-click")

    assert ["Source stale"] =
             document
             |> LazyHTML.query(~s(button[data-widget-source-badge="stale"]))
             |> LazyHTML.attribute("data-widget-source-badge-label")

    assert ["source_inventory"] =
             document
             |> LazyHTML.query(~s(button[data-widget-source-badge="stale"]))
             |> LazyHTML.attribute("data-widget-source-badge-inventory-action")

    assert [inventory_query] =
             document
             |> LazyHTML.query(~s(button[data-widget-source-badge="stale"]))
             |> LazyHTML.attribute("data-widget-source-badge-inventory-query")

    assert inventory_query =~ "contact_id=contact-1"
    assert inventory_query =~ "data_source_id=questdb-flight"
    assert inventory_query =~ "source_binding_id=binding-flight"
    assert inventory_query =~ "source_endpoint_id=endpoint-1"

    assert [href] =
             document
             |> LazyHTML.query(~s(a[data-widget-source-badge-inventory-open="stale"]))
             |> LazyHTML.attribute("href")

    assert href =~ "/missions/mission-1/ops/data-sources?"
    assert href =~ "data_source_id=questdb-flight"
  end

  test "source_status_badge renders passive badge without evidence context" do
    html =
      render_component(&WidgetSourceStatusComponents.source_status_badge/1,
        source_status: %{state: :no_data, severity: :info, data_state: :no_data},
        mission_id: "mission-1"
      )

    document = LazyHTML.from_fragment(html)

    assert ["none"] =
             document
             |> LazyHTML.query(~s(span[data-widget-source-badge="no_data"]))
             |> LazyHTML.attribute("data-widget-source-badge-action")

    assert [] =
             document
             |> LazyHTML.query(~s(button[data-widget-source-badge="no_data"]))
             |> LazyHTML.attribute("phx-click")
  end

  test "source_status_badge renders full no-data source context" do
    html =
      render_component(&WidgetSourceStatusComponents.source_status_badge/1,
        source_status: no_data_source_status(),
        mission_id: "mission-1"
      )

    document = LazyHTML.from_fragment(html)

    assert ["open_evidence"] =
             document
             |> LazyHTML.query(~s(button[data-widget-source-badge="no_data"]))
             |> LazyHTML.attribute("phx-click")

    assert ["No source"] =
             document
             |> LazyHTML.query(~s(button[data-widget-source-badge="no_data"]))
             |> LazyHTML.attribute("data-widget-source-badge-label")

    assert ["info"] =
             document
             |> LazyHTML.query(~s(button[data-widget-source-badge="no_data"]))
             |> LazyHTML.attribute("data-widget-source-badge-severity")

    assert ["operational_observables"] =
             document
             |> LazyHTML.query(~s(button[data-widget-source-badge="no_data"]))
             |> LazyHTML.attribute("data-widget-source-badge-source")

    assert ["managed_operational_observables"] =
             document
             |> LazyHTML.query(~s(button[data-widget-source-badge="no_data"]))
             |> LazyHTML.attribute("data-widget-source-badge-data-source")

    assert ["default_flight_operational_observables"] =
             document
             |> LazyHTML.query(~s(button[data-widget-source-badge="no_data"]))
             |> LazyHTML.attribute("data-widget-source-badge-binding")

    assert ["archive"] =
             document
             |> LazyHTML.query(~s(button[data-widget-source-badge="no_data"]))
             |> LazyHTML.attribute("data-widget-source-badge-time-mode")

    assert ["link"] =
             document
             |> LazyHTML.query(~s(button[data-widget-source-badge="no_data"]))
             |> LazyHTML.attribute("data-widget-source-badge-scope-kind")

    assert ["link-alpha"] =
             document
             |> LazyHTML.query(~s(button[data-widget-source-badge="no_data"]))
             |> LazyHTML.attribute("data-widget-source-badge-scope-id")

    assert ["scope_no_data"] =
             document
             |> LazyHTML.query(~s(button[data-widget-source-badge="no_data"]))
             |> LazyHTML.attribute("data-widget-source-badge-empty-reason")

    assert [inventory_query] =
             document
             |> LazyHTML.query(~s(button[data-widget-source-badge="no_data"]))
             |> LazyHTML.attribute("data-widget-source-badge-inventory-query")

    assert inventory_query =~ "data_source_id=managed_operational_observables"
    assert inventory_query =~ "logical_source=operational_observables"
    assert inventory_query =~ "scope_id=link-alpha"
    assert inventory_query =~ "source_empty_reason=scope_no_data"

    assert [href] =
             document
             |> LazyHTML.query(~s(a[data-widget-source-badge-inventory-open="no_data"]))
             |> LazyHTML.attribute("href")

    assert href =~ "/missions/mission-1/ops/data-sources?"
    assert href =~ "data_source_id=managed_operational_observables"
  end

  test "source_status_badge renders partial source evidence as actionable warning" do
    html =
      render_component(&WidgetSourceStatusComponents.source_status_badge/1,
        source_status: %{
          state: :partial,
          severity: :warning,
          data_state: :ready,
          logical_sources: [:telemetry],
          data_source_ids: ["questdb-flight"],
          source_binding_ids: ["binding-flight"]
        },
        mission_id: "mission-1"
      )

    document = LazyHTML.from_fragment(html)

    assert ["open_evidence"] =
             document
             |> LazyHTML.query(~s(button[data-widget-source-badge="partial"]))
             |> LazyHTML.attribute("phx-click")

    assert ["Source partial"] =
             document
             |> LazyHTML.query(~s(button[data-widget-source-badge="partial"]))
             |> LazyHTML.attribute("data-widget-source-badge-label")
  end

  test "source_status_badge renders degraded source health as actionable warning" do
    html =
      render_component(&WidgetSourceStatusComponents.source_status_badge/1,
        source_status: %{
          state: :degraded,
          severity: :warning,
          data_state: :ready,
          logical_sources: [:telemetry],
          data_source_ids: ["questdb-flight"],
          source_binding_ids: ["binding-flight"],
          source_health_event_ids: ["source-health-event-1"]
        },
        mission_id: "mission-1"
      )

    document = LazyHTML.from_fragment(html)

    assert ["open_evidence"] =
             document
             |> LazyHTML.query(~s(button[data-widget-source-badge="degraded"]))
             |> LazyHTML.attribute("phx-click")

    assert ["Source degraded"] =
             document
             |> LazyHTML.query(~s(button[data-widget-source-badge="degraded"]))
             |> LazyHTML.attribute("data-widget-source-badge-label")

    assert ["warning"] =
             document
             |> LazyHTML.query(~s(button[data-widget-source-badge="degraded"]))
             |> LazyHTML.attribute("data-widget-source-badge-severity")
  end

  test "widget_query_diagnostics exposes query context and evidence attrs" do
    data = %{source_status: source_status()}

    html =
      render_component(&WidgetSourceStatusComponents.widget_query_diagnostics/1,
        widget: widget(),
        placement_id: "placement-1",
        data: data,
        data_view: "all_revisions",
        compare_data_view: "canonical",
        warnings: [%{code_text: "stale_data"}]
      )

    document = LazyHTML.from_fragment(html)

    assert ["all_revisions"] =
             document
             |> LazyHTML.query(~s([data-widget-query-diagnostics]))
             |> LazyHTML.attribute("data-widget-query-data-view")

    assert ["canonical"] =
             document
             |> LazyHTML.query(~s([data-widget-query-diagnostics]))
             |> LazyHTML.attribute("data-widget-query-compare-data-view")

    assert ["telemetry"] =
             document
             |> LazyHTML.query(~s([data-widget-query-diagnostics]))
             |> LazyHTML.attribute("data-widget-query-binding-source")

    assert ["fixed"] =
             document
             |> LazyHTML.query(~s([data-widget-query-diagnostics]))
             |> LazyHTML.attribute("data-widget-query-binding-mode")

    assert ["HK.voltage"] =
             document
             |> LazyHTML.query(~s([data-widget-query-diagnostics]))
             |> LazyHTML.attribute("data-widget-query-observables")

    assert ["stale"] =
             document
             |> LazyHTML.query(~s([data-widget-query-diagnostics]))
             |> LazyHTML.attribute("data-widget-query-source-state")

    assert "archive/receipt_time" =
             document
             |> LazyHTML.query(~s([data-widget-query-value="time"]))
             |> LazyHTML.text()
             |> String.trim()

    assert ["query"] =
             document
             |> LazyHTML.query(~s([data-widget-query-evidence-open]))
             |> LazyHTML.attribute("phx-value-kind")

    assert ["Voltage"] =
             document
             |> LazyHTML.query(~s([data-widget-query-evidence-open]))
             |> LazyHTML.attribute("phx-value-widget-title")

    assert ["stale"] =
             document
             |> LazyHTML.query(~s([data-widget-query-evidence-open]))
             |> LazyHTML.attribute("phx-value-source-evidence-state")

    assert ["stale_data"] =
             document
             |> LazyHTML.query(~s([data-widget-query-evidence-open]))
             |> LazyHTML.attribute("phx-value-widget-warning-codes")
  end

  test "source status and diagnostics predicates classify displayable states" do
    assert WidgetSourceStatusComponents.source_status_badge?(%{
             source_status: %{state: :retention_gap}
           })

    assert WidgetSourceStatusComponents.source_status_badge?(%{
             source_status: %{state: :degraded}
           })

    refute WidgetSourceStatusComponents.source_status_badge?(%{source_status: %{state: :fresh}})

    assert WidgetSourceStatusComponents.widget_query_diagnostics?(
             widget(),
             %{source_status: source_status()},
             "canonical",
             nil
           )
  end

  defp widget do
    %{
      title: "Voltage",
      binding: %{
        source: :telemetry,
        mode: :fixed,
        point_id: "HK.voltage",
        sampling: :latest
      },
      options: %{window_seconds: 300}
    }
  end

  defp source_status do
    %{
      state: :stale,
      severity: :warning,
      data_state: :ready,
      stale?: true,
      warning_codes: [:stale_data],
      source_request_ids: ["source-req-1"],
      logical_sources: [:telemetry],
      data_source_ids: ["questdb-flight"],
      source_binding_ids: ["binding-flight"],
      realms: [:flight],
      time_modes: [:archive],
      time_axes: [:receipt_time],
      scope_kinds: [:spacecraft],
      scope_ids: ["spacecraft-1"],
      contact_ids: ["contact-1"],
      source_endpoint_ids: ["endpoint-1"],
      empty_reason: :contact_scope_no_data
    }
  end

  defp no_data_source_status do
    %{
      state: :no_data,
      severity: :info,
      data_state: :no_data,
      stale?: false,
      warning_codes: [],
      source_request_ids: ["source-request-empty"],
      logical_sources: [:operational_observables],
      data_source_ids: ["managed_operational_observables"],
      source_binding_ids: ["default_flight_operational_observables"],
      realms: [:flight],
      time_modes: [:archive],
      time_axes: [:generation_time],
      scope_kinds: [:link],
      scope_ids: ["link-alpha"],
      source_endpoint_ids: ["source-endpoint-alpha"],
      empty_reason: :scope_no_data
    }
  end
end
