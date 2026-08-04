defmodule Cadence.Dashboards.SourceFacts do
  @moduledoc """
  Current source facts needed before dashboard source-result cache reads.

  These facts are intentionally narrower than a resolved source result: they
  identify the active source binding, physical data source, current watermark,
  revision cursors, and source health without resolving display frames.
  """

  alias Cadence.Dashboards.{PlannedSourceRequest, RuntimeCacheKey}
  alias Cadence.Platform.ContractNormalization

  alias Cadence.DataSources.SourceWatermark

  alias Cadence.DataSources.{DataBinding, DataSource}

  @source_health_values [:healthy, :degraded, :unavailable, :unknown]

  @type source_health :: :healthy | :degraded | :unavailable | :unknown

  @type t :: %__MODULE__{
          source_binding: DataBinding.t() | nil,
          source_binding_segments: [map()],
          data_source: DataSource.t() | nil,
          watermark: SourceWatermark.t() | nil,
          watermarks: [SourceWatermark.t()],
          data_revision: term(),
          correction_cursor: term(),
          backfill_cursor: term(),
          source_health: source_health(),
          meta: map()
        }

  defstruct [
    :source_binding,
    :data_source,
    :watermark,
    :data_revision,
    :correction_cursor,
    :backfill_cursor,
    source_binding_segments: [],
    watermarks: [],
    source_health: :healthy,
    meta: %{}
  ]

  @spec source_health_values() :: [source_health()]
  def source_health_values, do: @source_health_values

  @spec new(map() | t()) :: t()
  def new(attrs), do: normalize(attrs)

  @spec normalize(map() | t()) :: t() | nil
  def normalize(%__MODULE__{} = facts) do
    %__MODULE__{
      facts
      | watermark: normalize_optional_watermark(facts.watermark),
        watermarks: normalize_watermarks(facts.watermarks),
        source_binding_segments:
          ContractNormalization.list_or_default(facts.source_binding_segments),
        source_health:
          ContractNormalization.known_atom(facts.source_health, @source_health_values),
        meta: ContractNormalization.map_or_default(facts.meta)
    }
  end

  def normalize(facts) when is_map(facts) do
    %__MODULE__{
      source_binding: ContractNormalization.attr(facts, :source_binding),
      data_source: ContractNormalization.attr(facts, :data_source),
      watermark:
        facts
        |> ContractNormalization.attr(:watermark)
        |> normalize_optional_watermark(),
      watermarks:
        facts
        |> ContractNormalization.attr(:watermarks, [])
        |> normalize_watermarks(),
      data_revision: ContractNormalization.attr(facts, :data_revision),
      correction_cursor: ContractNormalization.attr(facts, :correction_cursor),
      backfill_cursor: ContractNormalization.attr(facts, :backfill_cursor),
      source_binding_segments:
        facts
        |> ContractNormalization.attr(:source_binding_segments, [])
        |> ContractNormalization.list_or_default(),
      source_health:
        facts
        |> ContractNormalization.attr(:source_health, :healthy)
        |> ContractNormalization.known_atom(@source_health_values),
      meta:
        facts
        |> ContractNormalization.attr(:meta, %{})
        |> ContractNormalization.map_or_default()
    }
  end

  def normalize(_other), do: nil

  @spec runtime_cache_key(PlannedSourceRequest.t(), t(), keyword()) :: RuntimeCacheKey.t()
  def runtime_cache_key(%PlannedSourceRequest{} = request, %__MODULE__{} = facts, opts \\ [])
      when is_list(opts) do
    facts = normalize(facts)

    RuntimeCacheKey.source_result(request,
      cache_policy: Keyword.get(opts, :cache_policy, :live),
      source_binding: facts.source_binding,
      source_binding_segments: facts.source_binding_segments,
      data_source: facts.data_source,
      freshness_policy: Keyword.get(opts, :freshness_policy, %{}),
      watermark: facts.watermark,
      data_revision: facts.data_revision,
      correction_cursor: facts.correction_cursor,
      backfill_cursor: facts.backfill_cursor
    )
  end

  defp normalize_optional_watermark(nil), do: nil

  defp normalize_optional_watermark(%SourceWatermark{} = watermark),
    do: SourceWatermark.normalize(watermark)

  defp normalize_optional_watermark(watermark) when is_map(watermark),
    do: SourceWatermark.normalize(watermark)

  defp normalize_optional_watermark(watermark), do: watermark

  defp normalize_watermarks(watermarks) when is_list(watermarks),
    do: Enum.map(watermarks, &normalize_optional_watermark/1)

  defp normalize_watermarks(watermarks), do: watermarks
end
