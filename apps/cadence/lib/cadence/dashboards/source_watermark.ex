defmodule Cadence.Dashboards.SourceWatermark do
  @moduledoc """
  Freshness and completeness marker returned by dashboard source adapters.

  A watermark is scoped to one planned source request. Some sources can provide
  authoritative completeness intervals; others start with an explicit
  `:unknown` confidence so dashboard callers can surface stale-data uncertainty
  without depending on source-specific metadata shapes.
  """

  alias Cadence.Dashboards.ContractNormalization

  @logical_sources [:telemetry, :limits, :events, :operational_observables]
  @confidences [:authoritative, :best_effort, :unknown]
  @freshness_states [:fresh, :stale, :unknown, :retention_gap]

  @type confidence :: :authoritative | :best_effort | :unknown

  @type t :: %__MODULE__{
          logical_source: atom(),
          request_id: binary() | nil,
          source_binding_id: binary() | nil,
          data_source_id: binary() | nil,
          realm: binary() | atom() | nil,
          replay_run_id: binary() | nil,
          dataset: binary() | nil,
          scope: map() | nil,
          complete_through: DateTime.t() | nil,
          latest_receipt_time: DateTime.t() | nil,
          retention_starts_at: DateTime.t() | nil,
          sample_count: non_neg_integer() | nil,
          confidence: confidence(),
          freshness_state: :fresh | :stale | :unknown | :retention_gap | nil,
          freshness_policy: map(),
          freshness_checked_at: DateTime.t() | nil,
          meta: map()
        }

  defstruct [
    :logical_source,
    :request_id,
    :source_binding_id,
    :data_source_id,
    :realm,
    :replay_run_id,
    :dataset,
    :scope,
    :complete_through,
    :latest_receipt_time,
    :retention_starts_at,
    :sample_count,
    :freshness_state,
    :freshness_checked_at,
    confidence: :unknown,
    freshness_policy: %{},
    meta: %{}
  ]

  @spec logical_sources() :: [atom()]
  def logical_sources, do: @logical_sources

  @spec logical_source?(term()) :: boolean()
  def logical_source?(logical_source), do: logical_source in @logical_sources

  @spec confidences() :: [confidence()]
  def confidences, do: @confidences

  @spec confidence?(term()) :: boolean()
  def confidence?(confidence), do: confidence in @confidences

  @spec freshness_states() :: [atom()]
  def freshness_states, do: @freshness_states

  @spec freshness_state?(term()) :: boolean()
  def freshness_state?(freshness_state), do: freshness_state in @freshness_states

  @spec new(map() | t()) :: t()
  def new(attrs), do: normalize(attrs)

  @spec normalize(map() | t()) :: t()
  def normalize(%__MODULE__{} = watermark) do
    %__MODULE__{
      watermark
      | logical_source:
          ContractNormalization.known_atom(watermark.logical_source, @logical_sources),
        scope: ContractNormalization.optional_map(watermark.scope),
        confidence: ContractNormalization.known_atom(watermark.confidence, @confidences),
        freshness_state:
          ContractNormalization.known_atom(watermark.freshness_state, @freshness_states),
        freshness_policy: ContractNormalization.map_or_default(watermark.freshness_policy),
        meta: ContractNormalization.map_or_default(watermark.meta)
    }
  end

  def normalize(watermark) when is_map(watermark) do
    %__MODULE__{
      logical_source:
        watermark
        |> ContractNormalization.attr(:logical_source)
        |> ContractNormalization.known_atom(@logical_sources),
      request_id: ContractNormalization.attr(watermark, :request_id),
      source_binding_id: ContractNormalization.attr(watermark, :source_binding_id),
      data_source_id: ContractNormalization.attr(watermark, :data_source_id),
      realm: ContractNormalization.attr(watermark, :realm),
      replay_run_id: ContractNormalization.attr(watermark, :replay_run_id),
      dataset: ContractNormalization.attr(watermark, :dataset),
      scope:
        watermark |> ContractNormalization.attr(:scope) |> ContractNormalization.optional_map(),
      complete_through: ContractNormalization.attr(watermark, :complete_through),
      latest_receipt_time: ContractNormalization.attr(watermark, :latest_receipt_time),
      retention_starts_at: ContractNormalization.attr(watermark, :retention_starts_at),
      sample_count: ContractNormalization.attr(watermark, :sample_count),
      confidence:
        watermark
        |> ContractNormalization.attr(:confidence, :unknown)
        |> ContractNormalization.known_atom(@confidences),
      freshness_state:
        watermark
        |> ContractNormalization.attr(:freshness_state)
        |> ContractNormalization.known_atom(@freshness_states),
      freshness_policy:
        watermark
        |> ContractNormalization.attr(:freshness_policy, %{})
        |> ContractNormalization.map_or_default(),
      freshness_checked_at: ContractNormalization.attr(watermark, :freshness_checked_at),
      meta:
        watermark
        |> ContractNormalization.attr(:meta, %{})
        |> ContractNormalization.map_or_default()
    }
  end
end
