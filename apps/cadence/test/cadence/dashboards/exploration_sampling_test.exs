defmodule Cadence.Dashboards.ExplorationSamplingTest do
  use Cadence.UnitCase, async: true
  import Cadence.Dashboards.EngineFixtures
  alias Cadence.Dashboards.{DashboardResolveRequest, Engine, RuntimeCacheKey}
  alias Cadence.Dashboards.Sources.Telemetry.QueryOptions

  test "ad-hoc row limits and ordering reach telemetry and participate in cache identity" do
    document = document()

    base = %DashboardResolveRequest{
      organization_id: document.organization_id,
      mission_id: document.mission_id,
      dashboard_id: document.dashboard_id,
      document: document
    }

    results =
      for {limit, order} <- [{10, :asc}, {10, :desc}, {20, :desc}] do
        request = %{
          base
          | interaction_context: %{source_query: %{max_raw_points: limit, order: order}}
        }

        result = Engine.plan(request)
        [planned] = result.planned_source_requests
        assert planned.sampling.max_raw_points == limit
        assert planned.sampling.order == order
        {query, _} = QueryOptions.history(planned, nil, [])
        assert query[:limit] == limit and query[:order] == order
        {RuntimeCacheKey.plan(request).fingerprint, planned.request_id}
      end

    assert length(Enum.uniq(results)) == 3
    assert length(Enum.uniq_by(results, &elem(&1, 0))) == 3
    assert length(Enum.uniq_by(results, &elem(&1, 1))) == 3
    [ordinary] = Engine.plan(base).planned_source_requests
    assert ordinary.sampling.max_raw_points == 10_000
    refute Map.has_key?(ordinary.sampling, :order)
    assert elem(QueryOptions.history(ordinary, nil, []), 0)[:order] == :asc
  end

  test "malformed ad-hoc limits cannot widen a query" do
    document = document()

    for limits <- [
          %{max_raw_points: 1001, order: :asc},
          %{max_raw_points: 0, order: :asc},
          %{max_raw_points: 10, order: :unknown},
          %{max_raw_points: 10},
          %{max_raw_points: 10, order: :asc, source: :other}
        ] do
      assert_raise ArgumentError, "invalid bounded source query", fn ->
        Engine.plan(%DashboardResolveRequest{
          organization_id: document.organization_id,
          mission_id: document.mission_id,
          dashboard_id: document.dashboard_id,
          document: document,
          interaction_context: %{source_query: limits}
        })
      end
    end
  end

  defp document do
    document = load_fixture!("no_data_time_series.v1.json")
    [placement] = document.placements

    widget = %{
      placement.widget_def
      | binding: Map.put(placement.widget_def.binding, :sampling, :raw_series)
    }

    %{document | placements: [%{placement | widget_def: widget}]}
  end
end
