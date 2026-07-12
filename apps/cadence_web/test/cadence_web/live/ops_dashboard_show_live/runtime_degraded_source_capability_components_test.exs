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

    document = LazyHTML.from_fragment(html)

    assert ["1"] =
             document
             |> LazyHTML.query("#dashboard-source-capability-postures")
             |> LazyHTML.attribute("data-source-capability-posture-count")

    assert ["open_evidence"] =
             document
             |> LazyHTML.query(~s([data-source-capability-posture="req-telemetry"]))
             |> LazyHTML.attribute("phx-click")

    assert ["source"] =
             document
             |> LazyHTML.query(~s([data-source-capability-posture="req-telemetry"]))
             |> LazyHTML.attribute("phx-value-kind")

    assert ["execution"] =
             document
             |> LazyHTML.query(~s([data-source-capability-posture="req-telemetry"]))
             |> LazyHTML.attribute("phx-value-source-evidence-mode")

    assert ["fallback"] =
             document
             |> LazyHTML.query(~s([data-source-capability-posture="req-telemetry"]))
             |> LazyHTML.attribute("phx-value-source-capability-status")

    assert ["generation_time"] =
             document
             |> LazyHTML.query(~s([data-source-capability-posture="req-telemetry"]))
             |> LazyHTML.attribute("phx-value-requested-time-axis")

    assert ["receipt_time"] =
             document
             |> LazyHTML.query(~s([data-source-capability-posture="req-telemetry"]))
             |> LazyHTML.attribute("phx-value-executed-time-axis")

    assert ["link_rf_metric_history"] =
             document
             |> LazyHTML.query(~s([data-source-capability-posture="req-telemetry"]))
             |> LazyHTML.attribute("phx-value-requested-products")

    assert ["transport_bitrate_history"] =
             document
             |> LazyHTML.query(~s([data-source-capability-posture="req-telemetry"]))
             |> LazyHTML.attribute("phx-value-supported-products")

    assert ["link_rf_metric_history"] =
             document
             |> LazyHTML.query(~s([data-source-capability-posture="req-telemetry"]))
             |> LazyHTML.attribute("data-source-capability-requested-products")

    assert ["transport_bitrate_history"] =
             document
             |> LazyHTML.query(~s([data-source-capability-posture="req-telemetry"]))
             |> LazyHTML.attribute("data-source-capability-supported-products")

    assert ["binding-flight"] =
             document
             |> LazyHTML.query(~s([data-source-capability-posture="req-telemetry"]))
             |> LazyHTML.attribute("phx-value-source-binding-id")

    assert document
           |> LazyHTML.query(~s([data-source-capability-posture="req-telemetry"]))
           |> LazyHTML.text() =~ "products=transport_bitrate_history"

    assert "telemetry:req-telemetry:fallback" =
             document
             |> LazyHTML.query(~s([data-source-capability-posture="req-telemetry"] .font-medium))
             |> selected_text()
  end

  test "source_capability_postures renders nothing without posture evidence" do
    html =
      render_component(&RuntimeDegradedSourceComponents.source_capability_postures/1,
        postures: []
      )

    document = LazyHTML.from_fragment(html)

    assert [] =
             document
             |> LazyHTML.query("#dashboard-source-capability-postures")
             |> LazyHTML.attribute("id")
  end

  defp selected_text(document) do
    document
    |> LazyHTML.text()
    |> String.trim()
  end
end
