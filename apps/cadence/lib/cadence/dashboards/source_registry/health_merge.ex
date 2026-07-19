defmodule Cadence.Dashboards.SourceRegistry.HealthMerge do
  @moduledoc """
  Applies classified persisted source health to facts, metadata, and watermarks.
  """

  alias Cadence.Dashboards.{SourceFacts, SourceWatermark}
  alias Cadence.OperationalEvents.EffectiveInterval

  @spec merge_facts(SourceFacts.t(), map(), EffectiveInterval.t() | nil) :: SourceFacts.t()
  def merge_facts(%SourceFacts{} = facts, classification, interval)
      when is_map(classification) do
    meta =
      facts.meta
      |> classification_meta(classification, interval)

    facts =
      SourceFacts.new(%{
        facts
        | source_health: classification.source_health,
          meta: meta,
          watermark: put_watermark(facts.watermark, meta),
          watermarks: Enum.map(facts.watermarks, &put_watermark(&1, meta))
      })

    facts
  end

  @spec classification_meta(map(), map(), EffectiveInterval.t() | nil) :: map()
  def classification_meta(meta, classification, interval) do
    status = Map.get(classification, :status)

    meta
    |> ensure_map()
    |> Map.put(:source_health, classification.source_health)
    |> Map.put(:source_health_freshness, classification.freshness)
    |> Map.put(:source_health_reason, classification.reason)
    |> Map.put(:source_health_observed_at, classification.observed_at)
    |> Map.put(:source_health_last_seen_at, classification.last_seen_at)
    |> Map.put(:source_health_age_ms, classification.age_ms)
    |> Map.put(:source_health_max_age_ms, classification.max_age_ms)
    |> Map.put(:source_health_raw_source_health, classification.raw_source_health)
    |> Map.put(:source_health_raw_reason, classification.raw_reason)
    |> maybe_put(:source_health_probe_kind, source_health_payload_value(status, :probe_kind))
    |> maybe_put(
      :source_health_probe_message,
      source_health_payload_value(status, :probe_message)
    )
    |> maybe_put(
      :source_health_probe_metadata,
      source_health_payload_value(status, :probe_metadata)
    )
    |> maybe_put(
      :source_health_connection_test_result,
      source_health_payload_value(status, :connection_test_result)
    )
    |> maybe_put(
      :source_health_connection_test_kind,
      source_health_payload_value(status, :connection_test_kind)
    )
    |> maybe_put(
      :source_health_connection_test_message,
      source_health_payload_value(status, :connection_test_message)
    )
    |> maybe_put(:durable_source_health?, not is_nil(status))
    |> maybe_put(:source_health_event_id, status && status.source_health_event_id)
    |> put_source_health_interval_meta(interval)
  end

  defp put_source_health_interval_meta(meta, %EffectiveInterval{} = interval) do
    interval_metadata = EffectiveInterval.metadata(interval)

    meta
    |> Map.put(:source_health_interval_id, interval.interval_id)
    |> Map.put(:source_health_interval_source_event_id, interval.source_event_id)
    |> Map.put(:source_health_interval, interval_metadata)
  end

  defp put_source_health_interval_meta(meta, _interval), do: meta

  defp source_health_payload_value(%{payload: payload}, key) when is_map(payload) do
    Map.get(payload, Atom.to_string(key), Map.get(payload, key))
  end

  defp source_health_payload_value(_status, _key), do: nil

  @spec put_watermark(SourceWatermark.t() | nil | term(), map()) ::
          SourceWatermark.t() | nil | term()
  def put_watermark(nil, _meta), do: nil

  def put_watermark(%SourceWatermark{} = watermark, meta) when is_map(meta) do
    %SourceWatermark{
      watermark
      | meta:
          watermark.meta
          |> ensure_map()
          |> maybe_put(:source_health_event_id, Map.get(meta, :source_health_event_id))
          |> maybe_put(:source_health_reason, Map.get(meta, :source_health_reason))
          |> maybe_put(:source_health_probe_kind, Map.get(meta, :source_health_probe_kind))
          |> maybe_put(:source_health_probe_message, Map.get(meta, :source_health_probe_message))
          |> maybe_put(
            :source_health_probe_metadata,
            Map.get(meta, :source_health_probe_metadata)
          )
          |> maybe_put(
            :source_health_connection_test_result,
            Map.get(meta, :source_health_connection_test_result)
          )
          |> maybe_put(
            :source_health_connection_test_kind,
            Map.get(meta, :source_health_connection_test_kind)
          )
          |> maybe_put(
            :source_health_connection_test_message,
            Map.get(meta, :source_health_connection_test_message)
          )
    }
  end

  def put_watermark(watermark, _meta), do: watermark

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp ensure_map(map) when is_map(map), do: map
  defp ensure_map(_value), do: %{}
end
