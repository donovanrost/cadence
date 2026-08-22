defmodule Cadence.Dashboards.SourceRegistry.FactsAggregation do
  @moduledoc """
  Aggregates source facts collected across effective binding segments.
  """

  alias Cadence.Dashboards.{PlannedSourceRequest, SourceFacts}

  alias Cadence.DataSources.SourceWatermark

  @type segment_metadata_fun :: (term() -> map() | nil)

  @spec merge(PlannedSourceRequest.t(), [{term(), SourceFacts.t()}], segment_metadata_fun()) ::
          SourceFacts.t()
  def merge(%PlannedSourceRequest{} = request, segment_facts, segment_metadata)
      when is_list(segment_facts) and is_function(segment_metadata, 1) do
    segments =
      Enum.map(segment_facts, fn {resolved_binding, _facts} ->
        segment_metadata.(resolved_binding)
      end)

    facts = Enum.map(segment_facts, fn {_resolved_binding, facts} -> facts end)

    watermarks =
      facts
      |> Enum.flat_map(&fact_watermarks/1)
      |> Enum.map(fn %SourceWatermark{} = watermark ->
        %SourceWatermark{watermark | request_id: request.request_id}
      end)

    SourceFacts.new(%{
      source_binding_segments: segments,
      watermark: aggregate_source_watermark(request, watermarks, segments),
      watermarks: watermarks,
      data_revision: common_fact_value(facts, :data_revision),
      correction_cursor: common_fact_value(facts, :correction_cursor),
      backfill_cursor: common_fact_value(facts, :backfill_cursor),
      source_health: aggregate_source_health(facts),
      meta: %{
        logical_source: request.logical_source,
        segmented_source_bindings?: true,
        source_binding_segment_count: length(segments),
        source_binding_segments: segments,
        source_health_by_segment: source_health_by_segment(segment_facts, segment_metadata),
        capability_posture: aggregate_capability_posture(facts),
        capability_posture_by_segment:
          capability_posture_by_segment(segment_facts, segment_metadata),
        durable_source_health?: Enum.any?(facts, &get_in(&1.meta, [:durable_source_health?]))
      }
    })
  end

  defp fact_watermarks(%SourceFacts{watermarks: [_ | _] = watermarks}), do: watermarks
  defp fact_watermarks(%SourceFacts{watermark: %SourceWatermark{} = watermark}), do: [watermark]
  defp fact_watermarks(%SourceFacts{}), do: []

  defp aggregate_source_watermark(
         %PlannedSourceRequest{} = request,
         [%SourceWatermark{} | _rest] = watermarks,
         segments
       ) do
    %SourceWatermark{
      logical_source: request.logical_source,
      request_id: request.request_id,
      scope: request.scope_context,
      complete_through: minimum_watermark_datetime(watermarks, :complete_through),
      latest_receipt_time: maximum_watermark_datetime(watermarks, :latest_receipt_time),
      retention_starts_at: minimum_watermark_datetime(watermarks, :retention_starts_at),
      confidence: weakest_watermark_confidence(watermarks),
      freshness_state: aggregate_freshness_state(watermarks),
      meta: %{
        segmented_source_bindings?: true,
        source_binding_segment_count: length(segments),
        source_binding_segments: segments
      }
    }
  end

  defp aggregate_source_watermark(%PlannedSourceRequest{}, [], _segments), do: nil

  defp minimum_watermark_datetime(watermarks, key) do
    watermarks
    |> Enum.map(&Map.get(&1, key))
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(nil, &earlier_datetime/2)
  end

  defp maximum_watermark_datetime(watermarks, key) do
    watermarks
    |> Enum.map(&Map.get(&1, key))
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(nil, &later_datetime/2)
  end

  defp weakest_watermark_confidence(watermarks) do
    cond do
      Enum.any?(watermarks, &(&1.confidence == :unknown)) -> :unknown
      Enum.any?(watermarks, &(&1.confidence == :best_effort)) -> :best_effort
      true -> :authoritative
    end
  end

  defp aggregate_freshness_state(watermarks) do
    states = Enum.map(watermarks, & &1.freshness_state)

    cond do
      :retention_gap in states -> :retention_gap
      :stale in states -> :stale
      :unknown in states -> :unknown
      Enum.all?(states, &(&1 == :fresh)) -> :fresh
      true -> nil
    end
  end

  defp aggregate_source_health(facts) do
    health = Enum.map(facts, & &1.source_health)

    cond do
      :unavailable in health -> :unavailable
      :degraded in health -> :degraded
      :unknown in health -> :unknown
      Enum.all?(health, &(&1 == :healthy)) -> :healthy
      true -> :unknown
    end
  end

  defp source_health_by_segment(segment_facts, segment_metadata) do
    Enum.map(segment_facts, fn {resolved_binding, %SourceFacts{} = facts} ->
      segment_metadata.(resolved_binding)
      |> Map.put(:source_health, facts.source_health)
      |> Map.put(:source_health_reason, get_in(facts.meta, [:source_health_reason]))
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()
    end)
  end

  defp capability_posture_by_segment(segment_facts, segment_metadata) do
    segment_facts
    |> Enum.map(fn {resolved_binding, %SourceFacts{} = facts} ->
      posture = get_in(facts.meta, [:capability_posture])

      segment_metadata.(resolved_binding)
      |> Map.put(:capability_posture, posture)
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()
    end)
    |> Enum.reject(&(&1 == %{}))
  end

  defp aggregate_capability_posture(facts) do
    postures =
      facts
      |> Enum.map(&get_in(&1.meta, [:capability_posture]))
      |> Enum.reject(&is_nil/1)

    case postures do
      [] ->
        nil

      postures ->
        %{
          status: aggregate_capability_posture_status(postures),
          segment_count: length(postures),
          fallbacks: Enum.flat_map(postures, &List.wrap(Map.get(&1, :fallbacks, []))),
          unsupported: Enum.flat_map(postures, &List.wrap(Map.get(&1, :unsupported, [])))
        }
        |> Enum.reject(fn {_key, value} -> value in [nil, []] end)
        |> Map.new()
    end
  end

  defp aggregate_capability_posture_status(postures) do
    statuses = Enum.map(postures, &Map.get(&1, :status))

    cond do
      :unsupported in statuses -> :unsupported
      :fallback in statuses -> :fallback
      Enum.all?(statuses, &(&1 == :native)) -> :native
      true -> :unknown
    end
  end

  defp common_fact_value(facts, key) do
    facts
    |> Enum.map(&Map.get(&1, key))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> case do
      [value] -> value
      _other -> nil
    end
  end

  defp earlier_datetime(datetime, nil), do: datetime

  defp earlier_datetime(%DateTime{} = left, %DateTime{} = right) do
    if DateTime.compare(left, right) == :gt, do: right, else: left
  end

  defp later_datetime(datetime, nil), do: datetime

  defp later_datetime(%DateTime{} = left, %DateTime{} = right) do
    if DateTime.compare(left, right) == :lt, do: right, else: left
  end
end
