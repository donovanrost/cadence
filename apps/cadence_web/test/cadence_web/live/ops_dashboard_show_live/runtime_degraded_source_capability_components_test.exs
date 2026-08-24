defmodule CadenceWeb.OpsDashboardShowLive.RuntimeDegradedSourceCapabilityComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.RuntimeDegradedSourceComponents

  test "source_capability_postures renders operator evidence controls" do
    html =
      render_component(&RuntimeDegradedSourceComponents.source_capability_postures/1,
        postures: [
          %{
            request_id: "req-telemetry",
            logical_source: "telemetry",
            status: "fallback",
            requested_sampling: "latest",
            supported_sampling: "latest",
            requested_products: "link_rf_metric_history",
            supported_products: "transport_bitrate_history",
            requested_time_axis: "generation_time",
            executed_time_axis: "receipt_time",
            supported_time_axes: "receipt_time",
            fallbacks: "time_axis:generation_time:receipt_time:unsupported_time_axis",
            unsupported: "generation_time",
            source_binding_id: "binding-flight",
            data_source_id: "questdb-flight",
            realm: "flight"
          }
        ]
      )

    vue =
      LiveVue.Test.get_vue(html,
        id: "dashboard-source-capability-postures-component"
      )

    assert vue.component == "RuntimeDegradedSource"
    assert vue.id == "dashboard-source-capability-postures-component"
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.handlers == %{}
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    presentation = vue.props["presentation"]
    assert presentation["kind"] == "capability_postures"

    assert presentation |> Map.keys() |> Enum.sort() ==
             ["heading", "items", "items_container", "kind", "root"]

    assert presentation["root"] == %{
             "attrs" => %{
               "data-diagnostics-section" => "Source capability posture",
               "data-source-capability-posture-count" => "1"
             },
             "class" => "space-y-2",
             "id" => "dashboard-source-capability-postures"
           }

    assert presentation["root"]["attrs"]["data-source-capability-posture-count"] == "1"
    [posture] = presentation["items"]
    assert posture["attrs"]["phx-click"] == "open_evidence"
    assert posture["evidence_attrs"]["phx-value-kind"] == "source"
    assert posture["evidence_attrs"]["phx-value-source-evidence-mode"] == "execution"
    assert posture["evidence_attrs"]["phx-value-source-capability-status"] == "fallback"

    assert posture["evidence_attrs"]["phx-value-requested-time-axis"] ==
             "generation_time"

    assert posture["evidence_attrs"]["phx-value-executed-time-axis"] == "receipt_time"

    assert posture["evidence_attrs"]["phx-value-requested-products"] ==
             "link_rf_metric_history"

    assert posture["evidence_attrs"]["phx-value-supported-products"] ==
             "transport_bitrate_history"

    assert posture["attrs"]["data-source-capability-requested-products"] ==
             "link_rf_metric_history"

    assert posture["attrs"]["data-source-capability-supported-products"] ==
             "transport_bitrate_history"

    assert posture["evidence_attrs"]["phx-value-source-binding-id"] == "binding-flight"
    assert Enum.at(posture["fields"], 1)["text"] =~ "products=transport_bitrate_history"
    assert posture["primary"]["text"]["text"] == "telemetry:req-telemetry:fallback"

    assert posture["attrs"] == %{
             "data-source-capability-executed-axis" => "receipt_time",
             "data-source-capability-logical-source" => "telemetry",
             "data-source-capability-posture" => "req-telemetry",
             "data-source-capability-requested-axis" => "generation_time",
             "data-source-capability-requested-products" => "link_rf_metric_history",
             "data-source-capability-status" => "fallback",
             "data-source-capability-supported-axes" => "receipt_time",
             "data-source-capability-supported-products" => "transport_bitrate_history",
             "phx-click" => "open_evidence"
           }

    assert posture["evidence_attrs"] == %{
             "phx-value-data-source-id" => "questdb-flight",
             "phx-value-executed-time-axis" => "receipt_time",
             "phx-value-kind" => "source",
             "phx-value-logical-source" => "telemetry",
             "phx-value-realm" => "flight",
             "phx-value-requested-products" => "link_rf_metric_history",
             "phx-value-requested-sampling" => "latest",
             "phx-value-requested-time-axis" => "generation_time",
             "phx-value-source-binding-id" => "binding-flight",
             "phx-value-source-capability-fallbacks" =>
               "time_axis:generation_time:receipt_time:unsupported_time_axis",
             "phx-value-source-capability-status" => "fallback",
             "phx-value-source-capability-unsupported" => "generation_time",
             "phx-value-source-evidence-mode" => "execution",
             "phx-value-source-request-id" => "req-telemetry",
             "phx-value-supported-products" => "transport_bitrate_history",
             "phx-value-supported-sampling" => "latest",
             "phx-value-supported-time-axes" => "receipt_time"
           }

    assert posture["render_attrs"] == Map.merge(posture["attrs"], posture["evidence_attrs"])

    assert posture["key"] == "source-capability-posture-0"
    assert posture["type"] == "button"

    assert posture["class"] ==
             "w-full border border-base-content/15 bg-base-200/40 px-2 py-2 text-left text-xs hover:bg-base-200/70"

    assert posture["primary"] == %{
             "class" => "flex items-center gap-2",
             "icon" => %{
               "class" => "h-3.5 w-3.5 text-warning",
               "name" => "hero-arrow-path"
             },
             "text" => %{
               "class" => "font-medium text-base-content",
               "text" => "telemetry:req-telemetry:fallback"
             }
           }

    assert Enum.map(posture["fields"], &{&1["attrs"], &1["text"]}) == [
             {%{"data-source-capability-field" => "Clock"}, "generation_time -> receipt_time"},
             {%{"data-source-capability-field" => "Support"},
              "sampling=latest products=transport_bitrate_history axes=receipt_time fallback=time_axis:generation_time:receipt_time:unsupported_time_axis unsupported=generation_time"}
           ]

    assert Enum.map(posture["fields"], & &1["key"]) == ["clock", "support"]

    variant_html =
      render_component(&RuntimeDegradedSourceComponents.source_capability_postures/1,
        postures: [
          %{
            request_id: "req-unsupported",
            logical_source: "telemetry",
            status: "unsupported"
          },
          %{
            request_id: "req-supported",
            logical_source: "events",
            status: "supported"
          }
        ]
      )

    variant_items =
      variant_html
      |> LiveVue.Test.get_vue(id: "dashboard-source-capability-postures-component")
      |> Map.fetch!(:props)
      |> get_in(["presentation", "items"])

    assert Enum.map(variant_items, & &1["key"]) == [
             "source-capability-posture-0",
             "source-capability-posture-1"
           ]

    assert Enum.map(variant_items, & &1["primary"]["icon"]) == [
             %{
               "class" => "h-3.5 w-3.5 text-error",
               "name" => "hero-exclamation-triangle"
             },
             %{"class" => "h-3.5 w-3.5 text-success", "name" => "hero-check-circle"}
           ]

    assert Enum.map(variant_items, & &1["primary"]["text"]["text"]) == [
             "telemetry:req-unsupported:unsupported",
             "events:req-supported:supported"
           ]

    [unsupported, _supported] = variant_items

    assert unsupported["evidence_attrs"] == %{
             "phx-value-kind" => "source",
             "phx-value-logical-source" => "telemetry",
             "phx-value-source-capability-status" => "unsupported",
             "phx-value-source-evidence-mode" => "execution",
             "phx-value-source-request-id" => "req-unsupported"
           }

    assert unsupported["attrs"]["data-source-capability-supported-products"] == nil
  end

  test "source_capability_postures renders nothing without posture evidence" do
    html =
      render_component(&RuntimeDegradedSourceComponents.source_capability_postures/1,
        postures: []
      )

    assert [] =
             html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("#dashboard-source-capability-postures-component")
             |> LazyHTML.attribute("id")

    non_list_html =
      render_component(&RuntimeDegradedSourceComponents.source_capability_postures/1,
        postures: %{status: "unavailable"}
      )

    assert [] =
             non_list_html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("#dashboard-source-capability-postures-component")
             |> LazyHTML.attribute("id")
  end
end
