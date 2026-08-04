defmodule CadenceWeb.OpsDataSourcesLive.SourceContractTest do
  use ExUnit.Case, async: true

  alias Cadence.DataSources.{DataBinding, DataSource}
  alias CadenceWeb.OpsDataSourcesLive.{SourceContract, SourceFocus}

  test "compatible_sources/2 keeps active matching adapters in identifier order" do
    binding = %DataBinding{logical_source: :telemetry}

    sources = [
      data_source("telemetry-z", Cadence.Dashboards.Sources.Telemetry),
      data_source("limits", Cadence.Dashboards.Sources.Limits),
      data_source("telemetry-disabled", Cadence.Dashboards.Sources.Telemetry, status: :disabled),
      data_source("telemetry-a", Cadence.Dashboards.Sources.Telemetry)
    ]

    assert ["telemetry-a", "telemetry-z"] =
             sources
             |> SourceContract.compatible_sources(binding)
             |> Enum.map(& &1.data_source_id)
  end

  test "evaluates requested dashboard capabilities after physical source overlays" do
    focus =
      SourceFocus.from_params(%{
        "requested_sampling" => "bounded_history",
        "requested_products" => "bounded_receipt_time_history",
        "requested_value_kinds" => "engineering",
        "requested_shapes" => "scalar",
        "requested_time_axes" => "receipt_time"
      })

    compatible =
      data_source("history", Cadence.Dashboards.Sources.Telemetry,
        capabilities: %{
          range_scan?: true,
          supported_products: [:bounded_receipt_time_history]
        }
      )

    latest_only =
      data_source("latest", Cadence.Dashboards.Sources.Telemetry,
        capabilities: %{range_scan?: false, supported_products: [:latest_value]}
      )

    assert SourceContract.satisfies_focus?(compatible, focus)

    assert [
             sampling: ["bounded_history"],
             source_products: ["bounded_receipt_time_history"]
           ] = SourceContract.missing_requirements(latest_only, focus)
  end

  test "derives operational product families and raw-series products" do
    source =
      data_source(
        "operational",
        Cadence.Dashboards.Sources.OperationalObservables
      )

    capabilities = SourceContract.effective_capabilities(source)

    assert :link_rf in SourceContract.supported_product_families(capabilities)

    assert :link_rf_metric_history in SourceContract.supported_metric_history_products(
             capabilities
           )
  end

  defp data_source(data_source_id, adapter, attrs \\ []) do
    struct!(
      DataSource,
      Keyword.merge(
        [
          data_source_id: data_source_id,
          adapter: adapter
        ],
        attrs
      )
    )
  end
end
