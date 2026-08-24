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

    presentation = html |> cache_summary_vue() |> Map.fetch!(:props) |> Map.fetch!("presentation")

    assert "reused" =
             presentation["section"]["attributes"]["data-cache-classification"]

    assert "hit" = field_value(presentation["fields"]["rows"], "Plan")

    assert "hit stale" = field_value(presentation["fields"]["rows"], "Source")

    assert %{"visible" => false} = presentation["evidence"]

    assert presentation["section"] == %{
             "id" => "dashboard-cache-summary",
             "class" => "border border-base-300/70 bg-base-100/40 px-3 py-2 text-sm",
             "attributes" => %{
               "data-diagnostics-section" => "Cache state",
               "data-cache-classification" => "reused",
               "data-cache-plan" => "hit",
               "data-cache-source" => "hit stale",
               "data-cache-frame" => "miss"
             }
           }

    assert presentation["heading"] == %{"class" => "hud-label", "text" => "Cache state"}

    assert presentation["headline"] == %{
             "class" => "mt-1 text-base-content",
             "text" => "Dashboard reused part of the runtime cache."
           }

    assert presentation["fields"]["class"] ==
             "mt-2 grid grid-cols-[4.5rem_minmax(0,1fr)] gap-x-2 gap-y-1 text-xs"

    assert Enum.map(presentation["fields"]["rows"], &field_contract/1) == [
             {"plan", "Plan", "Plan", "hit"},
             {"source", "Source", "Source", "hit stale"},
             {"frame", "Frame", "Frame", "miss"}
           ]
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

    presentation = html |> cache_summary_vue() |> Map.fetch!(:props) |> Map.fetch!("presentation")
    evidence = presentation["evidence"]
    [item] = evidence["list"]["items"]

    assert "1" = evidence["section"]["attributes"]["data-cache-evidence-count"]

    assert "1" = evidence["section"]["attributes"]["data-cache-evidence-resolved"]

    assert "cache-evidence-1" = item["attributes"]["data-cache-evidence-id"]

    assert "open_evidence" = item["button"]["attributes"]["phx-click"]

    assert "source_degraded" = field_value(item["fields"], "Incident")

    assert "inspect_source" = field_value(item["fields"], "Action")

    assert "source_health_event" =
             item["attributes"]["data-cache-evidence-incident-target"]

    assert "source-health-event-1" =
             item["attributes"]["data-cache-evidence-incident-target-id"]

    assert "source health event:source-health-event-1" =
             field_value(item["fields"], "Evidence")

    assert evidence["visible"] == true

    assert evidence["section"] == %{
             "id" => "dashboard-cache-evidence",
             "class" => "mt-3 border-t border-base-300/70 pt-2",
             "attributes" => %{
               "data-cache-evidence-count" => "1",
               "data-cache-evidence-resolved" => "1",
               "data-cache-evidence-context-only" => "2",
               "data-cache-evidence-missing" => "3"
             }
           }

    assert evidence["heading"] == %{
             "class" => "hud-label text-[0.65rem]",
             "text" => "Cache evidence"
           }

    assert evidence["states"]["class"] == "mt-2 grid grid-cols-3 gap-2 text-xs"

    assert Enum.map(evidence["states"]["rows"], &state_field_contract/1) == [
             {"resolved", "Resolved", "Resolved", "1"},
             {"context-only", "Context", "Context only", "2"},
             {"missing", "Missing", "Missing", "3"}
           ]

    assert evidence["list"]["class"] == "mt-2 space-y-2"
    assert Enum.map(evidence["list"]["items"], & &1["key"]) == [0]

    assert item["attributes"] == %{
             "data-cache-evidence-id" => "cache-evidence-1",
             "data-cache-evidence-layer" => "source",
             "data-cache-evidence-status" => "stale",
             "data-cache-evidence-request-id" => "request-1",
             "data-cache-evidence-placement-id" => "placement-1",
             "data-cache-evidence-source" => "telemetry",
             "data-cache-evidence-source-binding-id" => "binding-flight",
             "data-cache-evidence-data-source-id" => "questdb-flight",
             "data-cache-evidence-reasons" => "source_degraded",
             "data-cache-evidence-state" => "resolved",
             "data-cache-evidence-incident-status" => "source_degraded",
             "data-cache-evidence-incident-severity" => "warning",
             "data-cache-evidence-incident-action" => "inspect_source",
             "data-cache-evidence-incident-runtime-action" => "wait_for_refresh",
             "data-cache-evidence-incident-target" => "source_health_event",
             "data-cache-evidence-incident-target-id" => "source-health-event-1",
             "data-cache-evidence-incident-kind" => "source_health_event"
           }

    assert item["button"] == %{
             "type" => "button",
             "class" =>
               "grid w-full grid-cols-[3.5rem_minmax(0,1fr)] gap-x-2 gap-y-1 border border-base-300/60 bg-base-200/20 px-2 py-2 text-left text-xs hover:bg-base-200/50",
             "attributes" => %{
               "data-cache-evidence-open" => "cache-evidence-1",
               "phx-click" => "open_evidence",
               "phx-value-kind" => "source",
               "phx-value-source-evidence-mode" => "execution",
               "phx-value-source-evidence-state" => "resolved",
               "phx-value-cache-evidence-layer" => "source",
               "phx-value-cache-evidence-status" => "stale",
               "phx-value-cache-evidence-reasons" => "source_degraded",
               "phx-value-source-request-id" => "request-1",
               "phx-value-logical-source" => "telemetry",
               "phx-value-data-source-id" => "questdb-flight",
               "phx-value-source-binding-id" => "binding-flight",
               "phx-value-requested-data-source-id" => "questdb-flight",
               "phx-value-requested-source-binding-id" => "binding-flight"
             }
           }

    assert Enum.map(item["fields"], &evidence_field_contract/1) == [
             {"layer", true, "Layer", "Layer", "source"},
             {"status", true, "Status", "Status", "stale"},
             {"request", true, "Request", "Request", "request-1"},
             {"placement", true, "Placement", "Placement", "placement-1"},
             {"source", true, "Source", "Source", "telemetry"},
             {"binding", true, "Binding", "Binding", "binding-flight"},
             {"data-source", true, "Data", "Data source", "questdb-flight"},
             {"reasons", true, "Why", "Reasons", "source_degraded"},
             {"incident", true, "Incident", "Incident", "source_degraded"},
             {"action", true, "Action", "Action", "inspect_source"},
             {"evidence", true, "Evidence", "Evidence",
              "source health event:source-health-event-1"}
           ]
  end

  test "cache_summary preserves raw attribute and body value semantics" do
    first_item = %{
      evidence_id: 7,
      layer: false,
      status: nil,
      request_id: true,
      placement_id: "",
      logical_source: "",
      source_binding_id: 8,
      data_source_id: false,
      reasons: nil,
      evidence_state: true,
      incident_status_text: "-",
      incident_severity: nil,
      incident_operator_action: "-",
      incident_runtime_action: false,
      incident_evidence_target: true,
      incident_evidence_target_id: "-",
      incident_evidence_kind: "",
      incident_evidence_kind_text: nil
    }

    second_item = %{
      first_item
      | evidence_id: "cache-evidence-2",
        layer: "frame",
        status: "hit",
        request_id: "request-2",
        placement_id: "-",
        logical_source: "limits",
        source_binding_id: "-",
        data_source_id: "-",
        reasons: "-",
        evidence_state: "missing",
        incident_severity: "-",
        incident_runtime_action: "-",
        incident_evidence_target: "-",
        incident_evidence_kind: "-",
        incident_evidence_kind_text: "-"
    }

    html =
      render_component(&RuntimeCacheSummaryComponents.cache_summary/1,
        summary: %{
          visible?: true,
          classification: false,
          plan: nil,
          source: true,
          frame: "",
          headline: 9,
          evidence_state_summary: %{resolved: false, context_only: nil, missing: true},
          drilldowns: [first_item, second_item]
        }
      )

    presentation = html |> cache_summary_vue() |> Map.fetch!(:props) |> Map.fetch!("presentation")
    root_attributes = presentation["section"]["attributes"]

    refute Map.has_key?(root_attributes, "data-cache-classification")
    refute Map.has_key?(root_attributes, "data-cache-plan")
    assert root_attributes["data-cache-source"] == ""
    assert root_attributes["data-cache-frame"] == ""
    assert presentation["headline"]["text"] == "9"

    assert Enum.map(presentation["fields"]["rows"], & &1["value"]) == ["", "true", ""]

    evidence = presentation["evidence"]
    evidence_attributes = evidence["section"]["attributes"]

    assert evidence_attributes["data-cache-evidence-count"] == "2"
    refute Map.has_key?(evidence_attributes, "data-cache-evidence-resolved")
    refute Map.has_key?(evidence_attributes, "data-cache-evidence-context-only")
    assert evidence_attributes["data-cache-evidence-missing"] == ""

    assert Enum.map(evidence["states"]["rows"], & &1["value"]) == ["false", "", "true"]

    [first, second] = evidence["list"]["items"]

    assert Enum.map(evidence["list"]["items"], fn item ->
             item["attributes"]["data-cache-evidence-id"]
           end) == ["7", "cache-evidence-2"]

    assert first["attributes"] == %{
             "data-cache-evidence-id" => "7",
             "data-cache-evidence-request-id" => "",
             "data-cache-evidence-placement-id" => "",
             "data-cache-evidence-source" => "",
             "data-cache-evidence-source-binding-id" => "8",
             "data-cache-evidence-state" => "",
             "data-cache-evidence-incident-status" => "-",
             "data-cache-evidence-incident-action" => "-",
             "data-cache-evidence-incident-target" => "",
             "data-cache-evidence-incident-target-id" => "-",
             "data-cache-evidence-incident-kind" => ""
           }

    assert first["button"]["attributes"] == %{
             "data-cache-evidence-open" => "7",
             "phx-click" => "open_evidence",
             "phx-value-kind" => "source",
             "phx-value-source-evidence-mode" => "health",
             "phx-value-source-evidence-state" => "true",
             "phx-value-cache-evidence-layer" => "false",
             "phx-value-source-request-id" => "true",
             "phx-value-data-source-id" => "false",
             "phx-value-source-binding-id" => "8",
             "phx-value-requested-data-source-id" => "false",
             "phx-value-requested-source-binding-id" => "8"
           }

    assert Enum.map(first["fields"], fn field ->
             {field["key"], field["value"], field["visible"]}
           end) == [
             {"layer", "false", true},
             {"status", "", true},
             {"request", "true", true},
             {"placement", "", true},
             {"source", "", true},
             {"binding", "8", true},
             {"data-source", "false", true},
             {"reasons", "", true},
             {"incident", "-", false},
             {"action", "-", false},
             {"evidence", ":-", false}
           ]

    assert second["key"] == 1

    assert second["fields"]
           |> Enum.filter(&(&1["key"] in ["placement", "incident", "action", "evidence"]))
           |> Enum.map(& &1["visible"]) == [false, false, false, false]
  end

  test "cache_summary renders nothing when hidden" do
    for visible? <- [false, nil, "true", 1] do
      html =
        render_component(&RuntimeCacheSummaryComponents.cache_summary/1,
          summary: %{visible?: visible?}
        )

      assert [] =
               html
               |> LazyHTML.from_fragment()
               |> LazyHTML.query("#dashboard-cache-summary-component")
               |> LazyHTML.attribute("id")
    end
  end

  defp cache_summary_vue(html) do
    vue = LiveVue.Test.get_vue(html, id: "dashboard-cache-summary-component")

    assert vue.id == "dashboard-cache-summary-component"
    assert vue.component == "RuntimeCacheSummary"
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.handlers == %{}
    assert vue.slots == %{}
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    vue
  end

  defp field_value(fields, data_label) do
    fields
    |> Enum.find(&(&1["attributes"]["data-cache-field"] == data_label))
    |> case do
      nil ->
        fields
        |> Enum.find(&(&1["attributes"]["data-cache-evidence-field"] == data_label))
        |> Map.fetch!("value")

      field ->
        Map.fetch!(field, "value")
    end
  end

  defp field_contract(field) do
    assert field["label_class"] == "text-base-content/60"
    assert field["value_class"] == "font-mono text-base-content break-all"

    {
      field["key"],
      field["label"],
      field["attributes"]["data-cache-field"],
      field["value"]
    }
  end

  defp state_field_contract(field) do
    assert field["label_class"] == "text-base-content/60"
    assert field["value_class"] == "font-mono text-base-content"

    {
      field["key"],
      field["label"],
      field["attributes"]["data-cache-evidence-state-field"],
      field["value"]
    }
  end

  defp evidence_field_contract(field) do
    assert field["label_class"] == "text-base-content/60"
    assert field["value_class"] == "font-mono text-base-content break-all"

    {
      field["key"],
      field["visible"],
      field["label"],
      field["attributes"]["data-cache-evidence-field"],
      field["value"]
    }
  end
end
