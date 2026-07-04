defmodule CadenceWeb.OpsDashboardShowLive.SourceHealthComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.Components
  alias CadenceWeb.OpsDashboardShowLive.SourceHealthComponents

  test "source health strip exposes aggregate and evidence attributes" do
    html =
      render_component(&SourceHealthComponents.source_health_strip/1,
        health: [
          source_health(
            logical_source_text: "Telemetry",
            state: :stale,
            state_text: "stale",
            source_cache_text: "stale rejected",
            frame_cache_text: "fresh",
            circuit_state: :open,
            circuit_state_text: "open",
            execution_status_text: "source execution failed",
            execution_severity_text: "error",
            execution_operator_action_text: "retry source execution",
            execution_runtime_action_text: "refresh_source_result",
            execution_degraded?: true,
            execution_actionable?: true,
            execution_retryable?: true
          ),
          source_health(
            logical_source_text: "Events",
            state: :fresh,
            state_text: "fresh",
            source_cache_text: "fresh",
            frame_cache_text: "",
            circuit_state: nil,
            circuit_state_text: nil,
            execution_status_text: nil,
            execution_severity_text: "",
            execution_operator_action_text: ""
          )
        ]
      )

    document = LazyHTML.from_fragment(html)

    assert ["Telemetry:stale,Events:fresh"] =
             document
             |> LazyHTML.query("#dashboard-source-health")
             |> LazyHTML.attribute("data-source-health")

    assert ["Telemetry:source=stale_rejected;frame=fresh,Events:source=fresh;frame=none"] =
             document
             |> LazyHTML.query("#dashboard-source-health")
             |> LazyHTML.attribute("data-source-cache")

    assert ["Telemetry:open,Events:none"] =
             document
             |> LazyHTML.query("#dashboard-source-health")
             |> LazyHTML.attribute("data-source-circuit")

    assert ["Telemetry:source_execution_failed,Events:none"] =
             document
             |> LazyHTML.query("#dashboard-source-health")
             |> LazyHTML.attribute("data-source-execution")

    assert ["Telemetry:error,Events:none"] =
             document
             |> LazyHTML.query("#dashboard-source-health")
             |> LazyHTML.attribute("data-source-execution-severity")

    assert ["Telemetry:retry_source_execution,Events:none"] =
             document
             |> LazyHTML.query("#dashboard-source-health")
             |> LazyHTML.attribute("data-source-execution-action")

    assert ["Telemetry"] =
             document
             |> LazyHTML.query(~s(summary[data-source-health-source="Telemetry"]))
             |> LazyHTML.attribute("data-source-health-source")

    assert ["true"] =
             document
             |> LazyHTML.query(~s(summary[data-source-health-source="Telemetry"]))
             |> LazyHTML.attribute("data-source-execution-degraded")

    assert ["true"] =
             document
             |> LazyHTML.query(~s(summary[data-source-health-source="Telemetry"]))
             |> LazyHTML.attribute("data-source-execution-actionable")

    assert ["true"] =
             document
             |> LazyHTML.query(~s(summary[data-source-health-source="Telemetry"]))
             |> LazyHTML.attribute("data-source-execution-retryable")

    assert ["open_evidence", "open_evidence"] =
             document
             |> LazyHTML.query(~s([data-source-evidence-open]))
             |> LazyHTML.attribute("phx-click")

    assert ["source", "source"] =
             document
             |> LazyHTML.query(~s([data-source-evidence-open]))
             |> LazyHTML.attribute("phx-value-kind")

    assert ["health", "health"] =
             document
             |> LazyHTML.query(~s([data-source-evidence-open]))
             |> LazyHTML.attribute("phx-value-source-evidence-mode")
  end

  test "Components source health wrapper delegates to extracted component" do
    html =
      render_component(&Components.source_health_strip/1,
        health: [source_health(logical_source_text: "Telemetry")]
      )

    assert html =~ ~s(id="dashboard-source-health")
    assert html =~ ~s(data-source-health-source="Telemetry")
  end

  defp source_health(overrides) do
    %{
      request_id: "req-telemetry",
      logical_source: "telemetry",
      logical_source_text: "Telemetry",
      realm: "flight",
      realm_text: "flight",
      data_source_id: "questdb-flight",
      source_binding_id: "binding-flight",
      label: "Telemetry / flight",
      state: :fresh,
      state_text: "fresh",
      confidence_text: "high",
      source_cache_text: "fresh",
      frame_cache_text: "fresh",
      circuit_state: nil,
      circuit_state_text: nil,
      source_warning_text: nil,
      execution_status_text: nil,
      execution_severity_text: nil,
      execution_operator_action_text: nil,
      execution_runtime_action_text: nil,
      execution_degraded?: false,
      execution_actionable?: false,
      execution_retryable?: false,
      source_health_event_id: "source-health-event-1",
      source_health_reason: "fresh",
      source_health_probe_kind: "cache",
      source_health_probe_message: "source cache is fresh",
      source_health_probe_metadata_text: "age_ms=10",
      detail_rows: [
        %{label: "Source binding", value: "binding-flight"},
        %{label: "Data source", value: "questdb-flight"}
      ]
    }
    |> Map.merge(Map.new(overrides))
  end
end
