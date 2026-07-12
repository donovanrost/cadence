defmodule CadenceWeb.OpsDashboardShowLive.RuntimeDegradedSourceComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.RuntimeDegradedSourceComponents

  test "degraded_source_summary renders visible degraded source fields" do
    html =
      render_component(&RuntimeDegradedSourceComponents.degraded_source_summary/1,
        summary: %{
          visible?: true,
          count: 1,
          identity: "telemetry:request-1",
          status: "source_degraded",
          runtime_action: "wait_for_refresh",
          operator_action: "inspect_source",
          realm: "flight",
          data_source_id: "questdb-flight",
          source_binding_id: "binding-flight",
          request_id: "request-1",
          headline: "Source execution degraded."
        }
      )

    document = LazyHTML.from_fragment(html)

    assert ["1"] =
             document
             |> LazyHTML.query("#dashboard-source-execution-degraded-summary")
             |> LazyHTML.attribute("data-source-execution-degraded-count")

    assert ["telemetry:request-1"] =
             document
             |> LazyHTML.query("#dashboard-source-execution-degraded-summary")
             |> LazyHTML.attribute("data-source-execution-degraded-identity")

    assert ["flight"] =
             document
             |> LazyHTML.query("#dashboard-source-execution-degraded-summary")
             |> LazyHTML.attribute("data-source-execution-realm")

    assert "source_degraded" =
             document
             |> LazyHTML.query(~s([data-source-execution-field="Status"]))
             |> selected_text()

    assert "wait_for_refresh" =
             document
             |> LazyHTML.query(~s([data-source-execution-field="Runtime"]))
             |> selected_text()

    assert "inspect_source" =
             document
             |> LazyHTML.query(~s([data-source-execution-field="Operator"]))
             |> selected_text()
  end

  test "degraded_source_summary renders nothing when hidden" do
    html =
      render_component(&RuntimeDegradedSourceComponents.degraded_source_summary/1,
        summary: %{visible?: false}
      )

    document = LazyHTML.from_fragment(html)

    assert [] =
             document
             |> LazyHTML.query("#dashboard-source-execution-degraded-summary")
             |> LazyHTML.attribute("id")
  end

  test "degraded_source_drilldowns renders open evidence controls" do
    html =
      render_component(&RuntimeDegradedSourceComponents.degraded_source_drilldowns/1,
        drilldowns: [
          %{
            request_id: "request-1",
            logical_source: "telemetry",
            status: "source_degraded",
            runtime_action: "wait_for_refresh",
            operator_action: "inspect_source",
            realm: "flight",
            data_source_id: "questdb-flight",
            source_binding_id: "binding-flight"
          },
          %{
            request_id: "request-2",
            logical_source: "events",
            status: "source_unavailable",
            runtime_action: "wait_for_source_health",
            operator_action: "inspect_source_health",
            realm: "rehearsal",
            data_source_id: "events-store",
            source_binding_id: "events-binding"
          }
        ]
      )

    document = LazyHTML.from_fragment(html)

    assert ["request-1", "request-2"] =
             document
             |> LazyHTML.query("[data-degraded-source-drilldown]")
             |> LazyHTML.attribute("data-degraded-source-drilldown")

    assert ["open_evidence", "open_evidence"] =
             document
             |> LazyHTML.query("[data-degraded-source-drilldown]")
             |> LazyHTML.attribute("phx-click")

    assert ["source", "source"] =
             document
             |> LazyHTML.query("[data-degraded-source-drilldown]")
             |> LazyHTML.attribute("phx-value-kind")

    assert ["execution", "execution"] =
             document
             |> LazyHTML.query("[data-degraded-source-drilldown]")
             |> LazyHTML.attribute("phx-value-source-evidence-mode")

    assert ["telemetry", "events"] =
             document
             |> LazyHTML.query("[data-degraded-source-drilldown]")
             |> LazyHTML.attribute("phx-value-logical-source")

    assert document
           |> LazyHTML.query("[data-degraded-source-drilldown]")
           |> selected_text() =~ "telemetry:request-1:source_degraded"

    assert document
           |> LazyHTML.query("[data-degraded-source-drilldown]")
           |> selected_text() =~ "wait_for_refresh:inspect_source"

    assert ["source_degraded", "source_unavailable"] =
             document
             |> LazyHTML.query("[data-degraded-source-drilldown]")
             |> LazyHTML.attribute("data-degraded-source-status")

    assert ["wait_for_refresh", "wait_for_source_health"] =
             document
             |> LazyHTML.query("[data-degraded-source-drilldown]")
             |> LazyHTML.attribute("data-degraded-source-runtime-action")

    assert document
           |> LazyHTML.query("[data-degraded-source-drilldown]")
           |> selected_text() =~ "events:request-2:source_unavailable"
  end

  test "degraded_source_drilldowns renders nothing without drilldowns" do
    html =
      render_component(&RuntimeDegradedSourceComponents.degraded_source_drilldowns/1,
        drilldowns: []
      )

    document = LazyHTML.from_fragment(html)

    assert [] =
             document
             |> LazyHTML.query("#dashboard-degraded-source-drilldowns")
             |> LazyHTML.attribute("id")
  end

  test "source_dependency_causes renders operator cause rows with upstream evidence controls" do
    html =
      render_component(&RuntimeDegradedSourceComponents.source_dependency_causes/1,
        dependencies: [
          %{
            request_id: "req-limits",
            request_logical_source: "limits",
            logical_source: "telemetry",
            reason: "limit_latest_sample_input",
            products: "latest_sample",
            upstream_request_id: "req-circuit",
            upstream_status: "source_degraded",
            upstream_runtime_action: "wait_for_source_health",
            upstream_operator_action: "inspect_source_health",
            upstream_cache_status: "stale",
            upstream_cache_reasons: "source_degraded",
            upstream_source_binding_id: "binding-flight",
            upstream_data_source_id: "questdb-flight",
            upstream_realm: "flight",
            upstream_watermark_freshness_state: "stale",
            upstream_watermark_confidence: "authoritative"
          }
        ]
      )

    document = LazyHTML.from_fragment(html)

    assert ["1"] =
             document
             |> LazyHTML.query("#dashboard-source-dependency-causes")
             |> LazyHTML.attribute("data-source-dependency-cause-count")

    assert ["req-limits"] =
             document
             |> LazyHTML.query("[data-source-dependency-cause]")
             |> LazyHTML.attribute("data-source-dependency-cause")

    assert ["telemetry"] =
             document
             |> LazyHTML.query("[data-source-dependency-cause]")
             |> LazyHTML.attribute("phx-value-logical-source")

    assert ["req-circuit"] =
             document
             |> LazyHTML.query("[data-source-dependency-cause]")
             |> LazyHTML.attribute("phx-value-source-request-id")

    assert ["execution"] =
             document
             |> LazyHTML.query("[data-source-dependency-cause]")
             |> LazyHTML.attribute("phx-value-source-evidence-mode")

    assert ["binding-flight"] =
             document
             |> LazyHTML.query("[data-source-dependency-cause]")
             |> LazyHTML.attribute("phx-value-source-binding-id")

    assert ["source_degraded"] =
             document
             |> LazyHTML.query("[data-source-dependency-cause]")
             |> LazyHTML.attribute("data-source-dependency-upstream-status")

    assert document
           |> LazyHTML.query("[data-source-dependency-cause]")
           |> selected_text() =~ "Limits waiting on telemetry input"

    assert "limits:req-limits -> telemetry:req-circuit" =
             document
             |> LazyHTML.query(~s([data-source-dependency-field="Path"]))
             |> selected_text()

    assert "source_degraded:wait_for_source_health:stale" =
             document
             |> LazyHTML.query(~s([data-source-dependency-field="Upstream"]))
             |> selected_text()
  end

  test "source_dependency_causes renders nothing without dependency evidence" do
    html =
      render_component(&RuntimeDegradedSourceComponents.source_dependency_causes/1,
        dependencies: []
      )

    document = LazyHTML.from_fragment(html)

    assert [] =
             document
             |> LazyHTML.query("#dashboard-source-dependency-causes")
             |> LazyHTML.attribute("id")
  end

  defp selected_text(document) do
    document
    |> LazyHTML.text()
    |> String.trim()
  end
end
