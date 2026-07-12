defmodule CadenceWeb.OpsDashboardShowLive.SourceExecutionRuntimeSummaryPostureTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.SourceExecutionRuntimeSummary
  alias CadenceWeb.OpsDashboardShowLive.SourceExecutionRuntimeSummaryFixtures

  test "build exposes source selections and capability postures" do
    summary =
      SourceExecutionRuntimeSummary.build(
        SourceExecutionRuntimeSummaryFixtures.degraded_source_result()
      )

    assert %{
             "req-telemetry" => %{
               selected_source_binding_id: "binding-flight",
               selected_data_source_id: "managed-questdb",
               strategy: :current_binding
             }
           } = summary.source_selections

    assert [
             %{
               request_id: "req-telemetry",
               logical_source: :telemetry,
               status: :fallback,
               requested_sampling: :latest,
               supported_sampling: [:latest],
               requested_products: [:link_rf_metric_history],
               supported_products: [:transport_bitrate_history],
               requested_time_axis: :generation_time,
               executed_time_axis: :receipt_time,
               supported_time_axes: [:receipt_time],
               source_binding_id: "binding-flight",
               data_source_id: "managed-questdb",
               realm: :flight
             }
           ] = summary.capability_postures
  end
end
