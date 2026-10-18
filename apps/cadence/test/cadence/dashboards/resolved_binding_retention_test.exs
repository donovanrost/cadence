defmodule Cadence.Dashboards.ResolvedBindingRetentionTest do
  use Cadence.UnitCase, async: true

  import Cadence.Dashboards.SourceRegistryFixtures

  alias Cadence.Dashboards.{
    DashboardContract,
    DashboardResolveResult,
    DataSourceRegistry,
    Field,
    Frame,
    PlannedSourceRequest,
    SourceRegistry,
    SourceResult
  }

  alias Cadence.Dashboards.Sources.Telemetry

  test "registry replaces adapter-supplied receipts with the binding actually executed" do
    request = source_request() |> PlannedSourceRequest.normalize()

    opts = [
      data_sources: [data_source("source-1", [])],
      data_bindings: [data_binding("source-1")],
      adapters: %{telemetry: __MODULE__},
      source_circuit_breaker?: false,
      record_source_health_events?: false,
      validate_dashboard_contract?: true
    ]

    assert {:ok, binding} = DataSourceRegistry.resolve(request, opts)
    result = SourceRegistry.resolve(request, opts)
    assert result.resolved_bindings == [binding]
    [frame] = result.frames
    assert frame.meta.data_source_id == binding.data_source.data_source_id
    assert frame.meta.source_binding_id == binding.binding.binding_id
    assert frame.meta.realm == binding.realm
    assert frame.meta.dataset == binding.dataset
    refute Map.has_key?(frame.meta, :source_binding_row_spans)
    refute Map.has_key?(frame.meta, :segmented_source_bindings?)
    refute Map.has_key?(result.meta, :resolved_bindings)
    assert :ok = DashboardContract.validate_source_result(result)
  end

  test "old results normalize without inventing missing binding evidence" do
    old_source = %SourceResult{request_id: "request"} |> Map.delete(:resolved_bindings)
    assert SourceResult.normalize(old_source).resolved_bindings == []
    old_result = %DashboardResolveResult{} |> Map.delete(:resolved_bindings_by_request_id)
    assert DashboardResolveResult.normalize(old_result).resolved_bindings_by_request_id == %{}
  end

  test "the source result contract rejects untyped binding evidence" do
    for value <- [nil, %{}, [%{binding: "forged"}]] do
      assert {:error, violations} =
               DashboardContract.validate_source_result(%SourceResult{
                 request_id: "request",
                 resolved_bindings: value
               })

      assert Enum.any?(violations, &match?([:resolved_bindings | _], &1.path))
    end
  end

  def capabilities, do: Telemetry.capabilities()

  def resolve(request, _opts),
    do:
      SourceResult.new(%{
        request_id: request.request_id,
        frames: [
          %Frame{
            frame_id: "adapter-frame",
            source: :telemetry,
            shape: :scalar,
            fields: [%Field{name: "value", kind: :number, values: [1]}],
            meta: %{
              data_source_id: "forged",
              source_binding_id: "forged",
              realm: :simulation,
              dataset: "forged",
              segmented_source_bindings?: true,
              source_binding_row_spans: [%{count: 1, source: %{data_source_id: "forged"}}]
            }
          }
        ],
        resolved_bindings: [%{data_source: "adapter-forgery"}]
      })
end
