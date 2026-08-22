defmodule CadenceWeb.OpsDashboardShowLive.RuntimeCacheSummaryComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.RuntimeCacheSummaryComponents

  test "cache_summary renders visible cache fields" do
    html =
      render_component(&RuntimeCacheSummaryComponents.cache_summary/1,
        summary: %{
          visible?: true,
          classification: "reused",
          plan: "hit",
          source: "hit stale",
          frame: "miss",
          headline: "Dashboard reused part of the runtime cache.",
          drilldowns: []
        }
      )

    document = LazyHTML.from_fragment(html)

    assert ["reused"] =
             document
             |> LazyHTML.query("#dashboard-cache-summary")
             |> LazyHTML.attribute("data-cache-classification")

    assert "hit" =
             document
             |> LazyHTML.query(~s([data-cache-field="Plan"]))
             |> selected_text()

    assert "hit stale" =
             document
             |> LazyHTML.query(~s([data-cache-field="Source"]))
             |> selected_text()

    assert [] =
             document
             |> LazyHTML.query("#dashboard-cache-evidence")
             |> LazyHTML.attribute("data-cache-evidence-count")
  end

  test "cache_summary renders cache evidence drilldowns" do
    html =
      render_component(&RuntimeCacheSummaryComponents.cache_summary/1,
        summary: %{
          visible?: true,
          classification: "stale",
          plan: "hit",
          source: "stale",
          frame: "miss",
          headline: "Dashboard encountered stale runtime cache entries.",
          evidence_state_summary: %{resolved: 1, context_only: 2, missing: 3},
          drilldowns: [
            %{
              evidence_id: "cache-evidence-1",
              layer: "source",
              status: "stale",
              request_id: "request-1",
              placement_id: "placement-1",
              logical_source: "telemetry",
              source_binding_id: "binding-flight",
              data_source_id: "questdb-flight",
              reasons: "source_degraded",
              evidence_state: "resolved",
              incident_status_text: "source_degraded",
              incident_severity: "warning",
              incident_operator_action: "inspect_source",
              incident_runtime_action: "wait_for_refresh",
              incident_evidence_target: "source_health_event",
              incident_evidence_target_id: "source-health-event-1",
              incident_evidence_kind: "source_health_event",
              incident_evidence_kind_text: "source health event",
              evidence_ref: "source:request-1",
              evidence_kind: "cache_entry",
              target: "runtime_cache",
              target_id: "request-1",
              source: "runtime",
              source_id: "request-1",
              title: "Cache evidence",
              message: "Source cache entry is stale.",
              status_text: "resolved",
              subject: "source_degraded",
              subject_rows: [],
              detail_rows: [],
              context_rows: [],
              related_links: [],
              actions: []
            }
          ]
        }
      )

    document = LazyHTML.from_fragment(html)

    assert ["1"] =
             document
             |> LazyHTML.query("#dashboard-cache-evidence")
             |> LazyHTML.attribute("data-cache-evidence-count")

    assert ["1"] =
             document
             |> LazyHTML.query("#dashboard-cache-evidence")
             |> LazyHTML.attribute("data-cache-evidence-resolved")

    assert ["cache-evidence-1"] =
             document
             |> LazyHTML.query("[data-cache-evidence-id]")
             |> LazyHTML.attribute("data-cache-evidence-id")

    assert ["open_evidence"] =
             document
             |> LazyHTML.query("[data-cache-evidence-open]")
             |> LazyHTML.attribute("phx-click")

    assert "source_degraded" =
             document
             |> LazyHTML.query(~s([data-cache-evidence-field="Incident"]))
             |> selected_text()

    assert "inspect_source" =
             document
             |> LazyHTML.query(~s([data-cache-evidence-field="Action"]))
             |> selected_text()

    assert ["source_health_event"] =
             document
             |> LazyHTML.query("[data-cache-evidence-id]")
             |> LazyHTML.attribute("data-cache-evidence-incident-target")

    assert ["source-health-event-1"] =
             document
             |> LazyHTML.query("[data-cache-evidence-id]")
             |> LazyHTML.attribute("data-cache-evidence-incident-target-id")

    assert "source health event:source-health-event-1" =
             document
             |> LazyHTML.query(~s([data-cache-evidence-field="Evidence"]))
             |> selected_text()
  end

  test "cache_summary renders nothing when hidden" do
    html =
      render_component(&RuntimeCacheSummaryComponents.cache_summary/1,
        summary: %{visible?: false}
      )

    document = LazyHTML.from_fragment(html)

    assert [] =
             document
             |> LazyHTML.query("#dashboard-cache-summary")
             |> LazyHTML.attribute("id")
  end

  defp selected_text(document) do
    document
    |> LazyHTML.text()
    |> String.trim()
  end
end
