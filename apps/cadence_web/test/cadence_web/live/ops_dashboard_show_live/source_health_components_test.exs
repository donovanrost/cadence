defmodule CadenceWeb.OpsDashboardShowLive.SourceHealthComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.SourceHealthComponents

  test "source health strip exposes aggregate and evidence attributes" do
    vue =
      source_health_vue([
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
      ])

    assert_vue_host(vue)
    presentation = vue.props["presentation"]

    assert presentation |> Map.keys() |> Enum.sort() == ["label", "root", "sources"]

    assert presentation["root"] == %{
             "id" => "dashboard-source-health",
             "class" =>
               "shrink-0 flex flex-wrap items-center gap-2 px-2 py-1 border-b border-base-300/60 bg-base-200/40 text-xs",
             "attrs" => %{
               "data-source-health" => "Telemetry:stale,Events:fresh",
               "data-source-cache" =>
                 "Telemetry:source=stale_rejected;frame=fresh,Events:source=fresh;frame=none",
               "data-source-circuit" => "Telemetry:open,Events:none",
               "data-source-execution" => "Telemetry:source_execution_failed,Events:none",
               "data-source-execution-severity" => "Telemetry:error,Events:none",
               "data-source-execution-action" => "Telemetry:retry_source_execution,Events:none"
             }
           }

    assert presentation["label"] == %{"class" => "hud-label", "text" => "Source status"}
    assert Enum.map(presentation["sources"], & &1["order"]) == [0, 1]
    [telemetry, events] = presentation["sources"]

    assert telemetry == %{
             "key" => "source-health-req-telemetry-questdb-flight-0",
             "order" => 0,
             "overlay" => %{
               "id" => "source-health-req-telemetry-questdb-flight",
               "label" => "Telemetry / flight",
               "class" => "cadence-overlay",
               "placement" => "bottom-end",
               "width" => "md",
               "attrs" => %{
                 "data-overlay-kind" => "popover",
                 "data-overlay-placement" => "bottom-end",
                 "data-source-health-detail" => "Telemetry:stale",
                 "data-source-cache-detail" => "Telemetry:stale rejected",
                 "data-source-circuit-detail" => "Telemetry:open",
                 "data-source-execution-detail" => "Telemetry:source execution failed",
                 "data-source-execution-action-detail" => "Telemetry:retry source execution"
               }
             },
             "trigger" => %{
               "id" => "source-health-req-telemetry-questdb-flight-trigger",
               "type" => "button",
               "class" => "cadence-overlay-trigger",
               "attrs" => %{
                 "data-overlay-trigger" => "",
                 "aria-haspopup" => "dialog",
                 "aria-expanded" => "false",
                 "aria-controls" => "source-health-req-telemetry-questdb-flight-panel",
                 "aria-label" => "Telemetry / flight"
               }
             },
             "badge" => %{
               "class" => "badge badge-xs cursor-pointer badge-warning",
               "text" => "Telemetry / flight",
               "attrs" => %{
                 "data-source-health-source" => "Telemetry",
                 "data-source-health-state" => "stale",
                 "data-source-cache-state" => "stale rejected",
                 "data-source-frame-cache-state" => "fresh",
                 "data-source-circuit-state" => "open",
                 "data-source-execution-status" => "source execution failed",
                 "data-source-execution-severity" => "error",
                 "data-source-execution-action" => "retry source execution",
                 "data-source-execution-runtime-action" => "refresh_source_result",
                 "data-source-execution-degraded" => "true",
                 "data-source-execution-actionable" => "true",
                 "data-source-execution-retryable" => "true",
                 "title" => "Telemetry / flight"
               }
             },
             "panel" => %{
               "id" => "source-health-req-telemetry-questdb-flight-panel",
               "class" => "cadence-overlay-panel cadence-popover-panel",
               "hidden" => true,
               "width" => "md",
               "attrs" => %{
                 "data-overlay-panel" => "",
                 "data-overlay-width" => "md",
                 "aria-label" => "Telemetry / flight"
               }
             },
             "details" => %{
               "class" => "p-2 text-xs",
               "heading" => %{
                 "class" => "font-semibold text-base-content",
                 "text" => "Telemetry / flight"
               },
               "prose" => %{
                 "class" => "mt-1 text-base-content/70",
                 "text" =>
                   "Realm flight; confidence high; source cache stale rejected; frame cache fresh; execution source execution failed; action retry source execution."
               },
               "circuit" => %{
                 "visible" => true,
                 "class" => "mt-1 text-error",
                 "text" => "Circuit open: "
               },
               "evidence" => evidence_presentation(),
               "rows_class" => "mt-2 grid grid-cols-[7rem_minmax(0,1fr)] gap-x-2 gap-y-1",
               "rows" => detail_rows()
             }
           }

    assert events == %{
             "key" => "source-health-req-telemetry-questdb-flight-1",
             "order" => 1,
             "overlay" => %{
               "id" => "source-health-req-telemetry-questdb-flight",
               "label" => "Telemetry / flight",
               "class" => "cadence-overlay",
               "placement" => "bottom-end",
               "width" => "md",
               "attrs" => %{
                 "data-overlay-kind" => "popover",
                 "data-overlay-placement" => "bottom-end",
                 "data-source-health-detail" => "Events:fresh",
                 "data-source-cache-detail" => "Events:fresh",
                 "data-source-circuit-detail" => "Events:",
                 "data-source-execution-detail" => "Events:",
                 "data-source-execution-action-detail" => "Events:"
               }
             },
             "trigger" => %{
               "id" => "source-health-req-telemetry-questdb-flight-trigger",
               "type" => "button",
               "class" => "cadence-overlay-trigger",
               "attrs" => %{
                 "data-overlay-trigger" => "",
                 "aria-haspopup" => "dialog",
                 "aria-expanded" => "false",
                 "aria-controls" => "source-health-req-telemetry-questdb-flight-panel",
                 "aria-label" => "Telemetry / flight"
               }
             },
             "badge" => %{
               "class" => "badge badge-xs cursor-pointer badge-success",
               "text" => "Telemetry / flight",
               "attrs" => %{
                 "data-source-health-source" => "Events",
                 "data-source-health-state" => "fresh",
                 "data-source-cache-state" => "fresh",
                 "data-source-frame-cache-state" => "",
                 "data-source-execution-severity" => "",
                 "data-source-execution-action" => "",
                 "data-source-execution-degraded" => "false",
                 "data-source-execution-actionable" => "false",
                 "data-source-execution-retryable" => "false",
                 "title" => "Telemetry / flight"
               }
             },
             "panel" => %{
               "id" => "source-health-req-telemetry-questdb-flight-panel",
               "class" => "cadence-overlay-panel cadence-popover-panel",
               "hidden" => true,
               "width" => "md",
               "attrs" => %{
                 "data-overlay-panel" => "",
                 "data-overlay-width" => "md",
                 "aria-label" => "Telemetry / flight"
               }
             },
             "details" => %{
               "class" => "p-2 text-xs",
               "heading" => %{
                 "class" => "font-semibold text-base-content",
                 "text" => "Telemetry / flight"
               },
               "prose" => %{
                 "class" => "mt-1 text-base-content/70",
                 "text" =>
                   "Realm flight; confidence high; source cache fresh; frame cache none; execution none; action none."
               },
               "circuit" => %{
                 "visible" => false,
                 "class" => "mt-1 text-error",
                 "text" => "Circuit : "
               },
               "evidence" => evidence_presentation(),
               "rows_class" => "mt-2 grid grid-cols-[7rem_minmax(0,1fr)] gap-x-2 gap-y-1",
               "rows" => detail_rows()
             }
           }
  end

  test "source health strip renders no island for an empty health list" do
    html =
      render_component(&SourceHealthComponents.source_health_strip/1,
        health: []
      )

    assert [] =
             html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("#dashboard-source-health-component")
             |> LazyHTML.attribute("id")
  end

  test "source health strip renders no island for nil and non-list health values" do
    Enum.each([nil, false, %{}], fn health ->
      html =
        render_component(&SourceHealthComponents.source_health_strip/1,
          health: health
        )

      assert [] =
               html
               |> LazyHTML.from_fragment()
               |> LazyHTML.query("#dashboard-source-health-component")
               |> LazyHTML.attribute("id")
    end)
  end

  test "direct attributes and body text preserve nil false true empty and number semantics" do
    values = [nil, false, true, "", 7]

    health =
      values
      |> Enum.with_index()
      |> Enum.map(fn {value, index} ->
        source_health(
          request_id: "edge-#{index}",
          logical_source: value,
          logical_source_text: "Edge#{index}",
          realm: value,
          realm_text: value,
          data_source_id: "edge-source-#{index}",
          source_binding_id: value,
          label: value,
          state: :other,
          state_text: value,
          confidence_text: value,
          source_cache_text: value,
          frame_cache_text: value,
          circuit_state: true,
          circuit_state_text: value,
          source_warning_text: value,
          execution_status_text: value,
          execution_severity_text: value,
          execution_operator_action_text: value,
          execution_runtime_action_text: value,
          execution_degraded?: value,
          execution_actionable?: value,
          execution_retryable?: value,
          source_health_event_id: value,
          source_health_reason: value,
          source_health_probe_kind: value,
          source_health_probe_message: value,
          source_health_probe_metadata_text: value,
          detail_rows: [%{label: value, value: value}]
        )
      end)

    presentation = source_health_vue(health).props["presentation"]

    assert presentation["root"]["attrs"] == %{
             "data-source-health" => "Edge0:,Edge1:false,Edge2:true,Edge3:,Edge4:7",
             "data-source-cache" =>
               "Edge0:source=none;frame=none,Edge1:source=false;frame=false,Edge2:source=true;frame=true,Edge3:source=none;frame=none,Edge4:source=7;frame=7",
             "data-source-circuit" => "Edge0:none,Edge1:false,Edge2:true,Edge3:none,Edge4:7",
             "data-source-execution" => "Edge0:none,Edge1:false,Edge2:true,Edge3:none,Edge4:7",
             "data-source-execution-severity" =>
               "Edge0:none,Edge1:false,Edge2:true,Edge3:none,Edge4:7",
             "data-source-execution-action" =>
               "Edge0:none,Edge1:false,Edge2:true,Edge3:none,Edge4:7"
           }

    expected_body = ["", "false", "true", "", "7"]
    expected_status = ["none", "false", "true", "none", "7"]
    expected_truth = ["false", "false", "true", "true", "true"]

    Enum.zip([presentation["sources"], values, expected_body, expected_status, expected_truth])
    |> Enum.each(fn {source, value, body, status, truth} ->
      assert source["badge"]["text"] == body
      assert source["overlay"]["label"] == body
      assert source["details"]["heading"]["text"] == body
      assert source["details"]["circuit"]["visible"] == true
      assert source["details"]["circuit"]["text"] == "Circuit #{body}: #{body}"

      assert source["details"]["prose"]["text"] ==
               "Realm #{body}; confidence #{body}; source cache #{status}; frame cache #{status}; execution #{status}; action #{status}."

      [row] = source["details"]["rows"]
      assert row["label"]["text"] == body
      assert row["value"]["text"] == body

      direct_attr_maps = [
        {source["trigger"]["attrs"], "aria-label"},
        {source["panel"]["attrs"], "aria-label"},
        {source["badge"]["attrs"], "title"},
        {source["badge"]["attrs"], "data-source-health-state"},
        {source["badge"]["attrs"], "data-source-cache-state"},
        {source["badge"]["attrs"], "data-source-frame-cache-state"},
        {source["badge"]["attrs"], "data-source-circuit-state"},
        {source["badge"]["attrs"], "data-source-execution-status"},
        {source["badge"]["attrs"], "data-source-execution-severity"},
        {source["badge"]["attrs"], "data-source-execution-action"},
        {source["badge"]["attrs"], "data-source-execution-runtime-action"},
        {row["value"]["attrs"], "data-source-health-field"}
      ]

      Enum.each(direct_attr_maps, fn {attrs, key} ->
        if value in [nil, false] do
          refute Map.has_key?(attrs, key)
        else
          assert attrs[key] == if(value == true, do: "", else: body)
        end
      end)

      assert source["badge"]["attrs"]["data-source-execution-degraded"] == truth
      assert source["badge"]["attrs"]["data-source-execution-actionable"] == truth
      assert source["badge"]["attrs"]["data-source-execution-retryable"] == truth

      evidence_attrs = source["details"]["evidence"]["attrs"]

      evidence_value_attrs = [
        "phx-value-logical-source",
        "phx-value-realm",
        "phx-value-source-binding-id",
        "phx-value-source-health-event-id",
        "phx-value-source-health-reason",
        "phx-value-source-health-probe-kind",
        "phx-value-source-health-probe-message",
        "phx-value-source-health-probe-metadata"
      ]

      Enum.each(evidence_value_attrs, fn key ->
        if value in [nil, ""] do
          refute Map.has_key?(evidence_attrs, key)
        else
          assert evidence_attrs[key] == body
        end
      end)
    end)

    assert presentation == Jason.decode!(Jason.encode!(presentation))
  end

  test "popover IDs preserve Elixir or fallback truthiness" do
    values = [nil, false, true, "", 7]

    presentation =
      values
      |> Enum.with_index()
      |> Enum.map(fn {value, index} ->
        source_health(
          request_id: value,
          logical_source_text: "Fallback#{index}",
          data_source_id: value
        )
      end)
      |> source_health_vue()
      |> Map.fetch!(:props)
      |> Map.fetch!("presentation")

    assert Enum.map(presentation["sources"], & &1["overlay"]["id"]) == [
             "source-health-Fallback0-default",
             "source-health-Fallback1-default",
             "source-health-true-true",
             "source-health--",
             "source-health-7-7"
           ]

    assert Enum.map(presentation["sources"], & &1["order"]) == [0, 1, 2, 3, 4]
    assert presentation == Jason.decode!(Jason.encode!(presentation))
  end

  defp source_health_vue(health) do
    render_component(&SourceHealthComponents.source_health_strip/1, health: health)
    |> LiveVue.Test.get_vue(id: "dashboard-source-health-component")
  end

  defp assert_vue_host(vue) do
    assert vue.component == "SourceHealth"
    assert vue.id == "dashboard-source-health-component"
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.handlers == %{}
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))
  end

  defp evidence_presentation do
    %{
      "type" => "button",
      "class" => "mt-2 btn btn-xs btn-outline w-full justify-start",
      "attrs" => %{
        "data-source-evidence-open" => "",
        "phx-click" => "open_evidence",
        "phx-value-data-source-id" => "questdb-flight",
        "phx-value-kind" => "source",
        "phx-value-logical-source" => "telemetry",
        "phx-value-realm" => "flight",
        "phx-value-source-binding-id" => "binding-flight",
        "phx-value-source-evidence-mode" => "health",
        "phx-value-source-health-event-id" => "source-health-event-1",
        "phx-value-source-health-probe-kind" => "cache",
        "phx-value-source-health-probe-message" => "source cache is fresh",
        "phx-value-source-health-probe-metadata" => "age_ms=10",
        "phx-value-source-health-reason" => "fresh",
        "phx-value-source-request-id" => "req-telemetry"
      },
      "icon" => %{
        "name" => "hero-document-magnifying-glass",
        "class" => "h-3.5 w-3.5"
      },
      "label" => "Inspect evidence"
    }
  end

  defp detail_rows do
    [
      %{
        "key" => "source-health-detail-row-0",
        "order" => 0,
        "label" => %{"class" => "text-base-content/60", "text" => "Source binding"},
        "value" => %{
          "class" => "font-mono text-base-content break-all",
          "text" => "binding-flight",
          "attrs" => %{"data-source-health-field" => "Source binding"}
        }
      },
      %{
        "key" => "source-health-detail-row-1",
        "order" => 1,
        "label" => %{"class" => "text-base-content/60", "text" => "Data source"},
        "value" => %{
          "class" => "font-mono text-base-content break-all",
          "text" => "questdb-flight",
          "attrs" => %{"data-source-health-field" => "Data source"}
        }
      }
    ]
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
