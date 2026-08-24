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

    presentation =
      html
      |> runtime_degraded_source_vue(
        "dashboard-source-execution-degraded-summary-component",
        "summary"
      )
      |> Map.fetch!(:props)
      |> Map.fetch!("presentation")

    assert presentation |> Map.keys() |> Enum.sort() ==
             ["fields", "fields_class", "headline", "heading", "kind", "root"]

    assert presentation["root"]["id"] == "dashboard-source-execution-degraded-summary"

    assert presentation["root"]["class"] ==
             "border border-warning/30 bg-warning/10 px-3 py-2 text-sm"

    assert presentation["heading"] == %{
             "class" => "hud-label",
             "text" => "Source execution degraded"
           }

    assert presentation["headline"] == %{
             "class" => "mt-1 text-base-content",
             "text" => "Source execution degraded."
           }

    attrs = presentation["root"]["attrs"]

    assert attrs["data-source-execution-degraded-count"] == "1"
    assert attrs["data-source-execution-degraded-identity"] == "telemetry:request-1"
    assert attrs["data-source-execution-realm"] == "flight"

    assert attrs == %{
             "data-diagnostics-section" => "Source execution degraded",
             "data-source-execution-binding" => "binding-flight",
             "data-source-execution-data-source" => "questdb-flight",
             "data-source-execution-degraded-count" => "1",
             "data-source-execution-degraded-identity" => "telemetry:request-1",
             "data-source-execution-degraded-status" => "source_degraded",
             "data-source-execution-operator-action" => "inspect_source",
             "data-source-execution-realm" => "flight",
             "data-source-execution-request" => "request-1",
             "data-source-execution-runtime-action" => "wait_for_refresh"
           }

    assert Enum.map(presentation["fields"], & &1["label"]["text"]) == [
             "Source",
             "Status",
             "Runtime",
             "Operator"
           ]

    assert Enum.map(presentation["fields"], & &1["key"]) == [
             "Source",
             "Status",
             "Runtime",
             "Operator"
           ]

    fields = Map.new(presentation["fields"], &{&1["label"]["text"], &1["value"]})

    assert fields["Status"]["text"] == "source_degraded"
    assert fields["Runtime"]["text"] == "wait_for_refresh"
    assert fields["Operator"]["text"] == "inspect_source"

    assert Enum.map(presentation["fields"], & &1["value"]["attrs"]) == [
             %{"data-source-execution-field" => "Source"},
             %{"data-source-execution-field" => "Status"},
             %{"data-source-execution-field" => "Runtime"},
             %{"data-source-execution-field" => "Operator"}
           ]

    assert Enum.uniq(Enum.map(presentation["fields"], & &1["value"]["class"])) == [
             "font-mono text-base-content break-all"
           ]
  end

  test "degraded_source_summary renders nothing when hidden" do
    html =
      render_component(&RuntimeDegradedSourceComponents.degraded_source_summary/1,
        summary: %{visible?: false}
      )

    assert [] =
             html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("#dashboard-source-execution-degraded-summary-component")
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

    presentation =
      html
      |> runtime_degraded_source_vue(
        "dashboard-degraded-source-drilldowns-component",
        "drilldowns"
      )
      |> Map.fetch!(:props)
      |> Map.fetch!("presentation")

    assert presentation |> Map.keys() |> Enum.sort() ==
             ["heading", "items", "items_container", "kind", "root"]

    assert presentation["root"] == %{
             "attrs" => %{"data-diagnostics-section" => "Degraded sources"},
             "class" => "space-y-2",
             "id" => nil
           }

    assert presentation["heading"] == %{"class" => "hud-label", "text" => "Degraded sources"}

    assert presentation["items_container"] == %{
             "class" => "space-y-2",
             "id" => "dashboard-degraded-source-drilldowns"
           }

    [telemetry, events] = presentation["items"]

    assert Enum.map(presentation["items"], & &1["key"]) == [
             "degraded-source-drilldown-0",
             "degraded-source-drilldown-1"
           ]

    assert Enum.map(presentation["items"], & &1["attrs"]["data-degraded-source-drilldown"]) ==
             ["request-1", "request-2"]

    assert Enum.map(presentation["items"], & &1["attrs"]["phx-click"]) == [
             "open_evidence",
             "open_evidence"
           ]

    assert Enum.map(presentation["items"], & &1["evidence_attrs"]["phx-value-kind"]) == [
             "source",
             "source"
           ]

    assert Enum.map(
             presentation["items"],
             & &1["evidence_attrs"]["phx-value-source-evidence-mode"]
           ) == ["execution", "execution"]

    assert Enum.map(
             presentation["items"],
             & &1["evidence_attrs"]["phx-value-logical-source"]
           ) == ["telemetry", "events"]

    assert telemetry["primary"]["text"]["text"] =~ "telemetry:request-1:source_degraded"
    assert hd(telemetry["fields"])["text"] =~ "wait_for_refresh:inspect_source"
    assert Enum.map(telemetry["fields"], & &1["key"]) == ["actions"]

    assert Enum.map(presentation["items"], & &1["attrs"]["data-degraded-source-status"]) ==
             ["source_degraded", "source_unavailable"]

    assert Enum.map(
             presentation["items"],
             & &1["attrs"]["data-degraded-source-runtime-action"]
           ) == ["wait_for_refresh", "wait_for_source_health"]

    assert events["primary"]["text"]["text"] =~ "events:request-2:source_unavailable"

    assert telemetry["attrs"] == %{
             "data-degraded-source-drilldown" => "request-1",
             "data-degraded-source-logical-source" => "telemetry",
             "data-degraded-source-operator-action" => "inspect_source",
             "data-degraded-source-runtime-action" => "wait_for_refresh",
             "data-degraded-source-status" => "source_degraded",
             "phx-click" => "open_evidence"
           }

    assert telemetry["evidence_attrs"] == %{
             "phx-value-data-source-id" => "questdb-flight",
             "phx-value-kind" => "source",
             "phx-value-logical-source" => "telemetry",
             "phx-value-realm" => "flight",
             "phx-value-source-binding-id" => "binding-flight",
             "phx-value-source-evidence-mode" => "execution",
             "phx-value-source-request-id" => "request-1"
           }

    assert events["evidence_attrs"] == %{
             "phx-value-data-source-id" => "events-store",
             "phx-value-kind" => "source",
             "phx-value-logical-source" => "events",
             "phx-value-realm" => "rehearsal",
             "phx-value-source-binding-id" => "events-binding",
             "phx-value-source-evidence-mode" => "execution",
             "phx-value-source-request-id" => "request-2"
           }

    assert telemetry["render_attrs"] == Map.merge(telemetry["attrs"], telemetry["evidence_attrs"])
    assert events["render_attrs"] == Map.merge(events["attrs"], events["evidence_attrs"])

    assert Enum.map(presentation["items"], & &1["type"]) == ["button", "button"]

    assert telemetry["class"] ==
             "w-full border border-warning/30 bg-warning/5 px-2 py-2 text-left text-xs hover:bg-warning/10"

    assert telemetry["primary"] == %{
             "class" => "flex items-center gap-2",
             "icon" => %{
               "class" => "h-3.5 w-3.5 text-warning",
               "name" => "hero-document-magnifying-glass"
             },
             "text" => %{
               "class" => "font-mono text-base-content break-all",
               "text" => "telemetry:request-1:source_degraded"
             }
           }
  end

  test "degraded_source_drilldowns renders nothing without drilldowns" do
    html =
      render_component(&RuntimeDegradedSourceComponents.degraded_source_drilldowns/1,
        drilldowns: []
      )

    assert [] =
             html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("#dashboard-degraded-source-drilldowns-component")
             |> LazyHTML.attribute("id")

    non_list_html =
      render_component(&RuntimeDegradedSourceComponents.degraded_source_drilldowns/1,
        drilldowns: nil
      )

    assert [] =
             non_list_html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("#dashboard-degraded-source-drilldowns-component")
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

    presentation =
      html
      |> runtime_degraded_source_vue(
        "dashboard-source-dependency-causes-component",
        "dependency_causes"
      )
      |> Map.fetch!(:props)
      |> Map.fetch!("presentation")

    assert presentation["root"]["attrs"]["data-source-dependency-cause-count"] == "1"
    [dependency] = presentation["items"]
    assert dependency["attrs"]["data-source-dependency-cause"] == "req-limits"
    assert dependency["evidence_attrs"]["phx-value-logical-source"] == "telemetry"
    assert dependency["evidence_attrs"]["phx-value-source-request-id"] == "req-circuit"
    assert dependency["evidence_attrs"]["phx-value-source-evidence-mode"] == "execution"
    assert dependency["evidence_attrs"]["phx-value-source-binding-id"] == "binding-flight"
    assert dependency["attrs"]["data-source-dependency-upstream-status"] == "source_degraded"
    assert dependency["primary"]["text"]["text"] =~ "Limits waiting on telemetry input"

    assert Enum.map(dependency["fields"], & &1["text"]) == [
             "limits:req-limits -> telemetry:req-circuit",
             "source_degraded:wait_for_source_health:stale"
           ]

    assert Enum.map(dependency["fields"], & &1["key"]) == ["path", "upstream"]

    assert Enum.map(dependency["fields"], & &1["attrs"]) == [
             %{"data-source-dependency-field" => "Path"},
             %{"data-source-dependency-field" => "Upstream"}
           ]

    assert dependency["attrs"] == %{
             "data-source-dependency-cause" => "req-limits",
             "data-source-dependency-request-source" => "limits",
             "data-source-dependency-upstream-request" => "req-circuit",
             "data-source-dependency-upstream-runtime-action" => "wait_for_source_health",
             "data-source-dependency-upstream-source" => "telemetry",
             "data-source-dependency-upstream-status" => "source_degraded",
             "data-source-dependency-upstream-watermark-state" => "stale",
             "phx-click" => "open_evidence"
           }

    assert dependency["evidence_attrs"] == %{
             "phx-value-data-source-id" => "questdb-flight",
             "phx-value-kind" => "source",
             "phx-value-logical-source" => "telemetry",
             "phx-value-realm" => "flight",
             "phx-value-source-binding-id" => "binding-flight",
             "phx-value-source-evidence-mode" => "execution",
             "phx-value-source-request-id" => "req-circuit"
           }

    assert dependency["render_attrs"] ==
             Map.merge(dependency["attrs"], dependency["evidence_attrs"])

    assert dependency["type"] == "button"

    assert dependency["class"] ==
             "w-full border border-warning/30 bg-warning/5 px-2 py-2 text-left text-xs hover:bg-warning/10"

    assert dependency["primary"]["icon"] == %{
             "class" => "h-3.5 w-3.5 text-warning",
             "name" => "hero-arrow-path"
           }
  end

  test "source_dependency_causes renders nothing without dependency evidence" do
    html =
      render_component(&RuntimeDegradedSourceComponents.source_dependency_causes/1,
        dependencies: []
      )

    assert [] =
             html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("#dashboard-source-dependency-causes-component")
             |> LazyHTML.attribute("id")

    non_list_html =
      render_component(&RuntimeDegradedSourceComponents.source_dependency_causes/1,
        dependencies: :unavailable
      )

    assert [] =
             non_list_html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("#dashboard-source-dependency-causes-component")
             |> LazyHTML.attribute("id")
  end

  defp runtime_degraded_source_vue(html, id, kind) do
    vue = LiveVue.Test.get_vue(html, id: id)

    assert vue.component == "RuntimeDegradedSource"
    assert vue.id == id
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.handlers == %{}
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))
    assert vue.props["presentation"]["kind"] == kind

    vue
  end
end
