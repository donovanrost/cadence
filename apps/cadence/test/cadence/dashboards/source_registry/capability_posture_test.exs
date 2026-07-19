defmodule Cadence.Dashboards.SourceRegistry.CapabilityPostureTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Dashboards.{PlannedSourceRequest, SourceCapabilities}
  alias Cadence.Dashboards.SourceRegistry.CapabilityPosture

  test "reports telemetry receipt-time fallback without marking the request unsupported" do
    request =
      request(:telemetry,
        sampling: %{mode: :latest, products: [:latest_value]},
        time_context: %{axis: :generation_time}
      )

    capabilities =
      capabilities(:telemetry,
        supported_sampling: [:latest],
        supported_products: [:latest_value],
        supported_time_axes: [:receipt_time]
      )

    assert %{
             status: :fallback,
             requested_time_axis: :generation_time,
             executed_time_axis: :receipt_time,
             fallbacks: [
               %{
                 capability: :time_axis,
                 requested: :generation_time,
                 executed: :receipt_time,
                 reason: :unsupported_time_axis
               }
             ]
           } = CapabilityPosture.build(request, capabilities)
  end

  test "reports unsupported sampling and products independently" do
    request =
      request(:telemetry,
        sampling: %{mode: :raw_series, products: [:bounded_generation_time_history]}
      )

    capabilities =
      capabilities(:telemetry,
        supported_sampling: [:latest],
        supported_products: [:latest_value],
        supported_time_axes: [:receipt_time]
      )

    posture = CapabilityPosture.build(request, capabilities)

    assert posture.status == :unsupported

    assert %{
             requested: :raw_series,
             supported: [:latest],
             fallback: :none
           } = unsupported(posture, :sampling)

    assert %{
             requested: [:bounded_generation_time_history],
             supported: [:latest_value],
             missing: [:bounded_generation_time_history],
             fallback: :none
           } = unsupported(posture, :products)
  end

  test "maps operational observables to supported source-backing products" do
    request =
      request(:operational_observables,
        observables: ["link.snr_db"],
        sampling: %{mode: :latest, products: [:link_rf]}
      )

    capabilities =
      capabilities(:operational_observables,
        supported_sampling: [:latest],
        supported_products: [:operational_latest],
        metadata: %{
          source_backing_contracts: [
            %{
              observables: ["link.snr_db", "link.eb_n0_db"],
              product: :operational_latest,
              sampling: :latest
            },
            %{
              observables: ["link.snr_db"],
              product: :link_rf_metric,
              sampling: :latest
            }
          ]
        }
      )

    assert %{
             status: :native,
             requested_products: [:link_rf_metric],
             supported_products: [:operational_latest]
           } = CapabilityPosture.build(request, capabilities)
  end

  defp request(logical_source, opts) do
    struct!(
      PlannedSourceRequest,
      Keyword.merge([request_id: "request-1", logical_source: logical_source], opts)
    )
  end

  defp capabilities(logical_source, opts) do
    struct!(
      SourceCapabilities,
      Keyword.merge([logical_source: logical_source], opts)
    )
  end

  defp unsupported(posture, capability) do
    Enum.find(posture.unsupported, &(&1.capability == capability))
  end
end
