defmodule Cadence.Dashboards.SourceWatermarkStatus do
  @moduledoc """
  Latest dashboard source-watermark projection for one concrete source identity.
  """

  alias Cadence.Dashboards.{SourceWatermark, SourceWatermarkEvent}

  @type t :: %__MODULE__{
          source_watermark_key: binary(),
          source_watermark_event_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          logical_source: atom() | binary(),
          data_source_id: binary(),
          source_binding_id: binary() | nil,
          realm: atom() | binary() | nil,
          replay_run_id: binary() | nil,
          dataset: binary() | nil,
          event_type: SourceWatermarkEvent.event_type(),
          complete_through: DateTime.t() | nil,
          previous_complete_through: DateTime.t() | nil,
          latest_receipt_time: DateTime.t() | nil,
          previous_latest_receipt_time: DateTime.t() | nil,
          retention_starts_at: DateTime.t() | nil,
          previous_retention_starts_at: DateTime.t() | nil,
          sample_count: non_neg_integer() | nil,
          confidence: SourceWatermarkEvent.confidence(),
          reason: atom() | binary() | nil,
          observed_at: DateTime.t(),
          last_seen_at: DateTime.t(),
          transition_count: non_neg_integer(),
          payload: map()
        }

  defstruct [
    :source_watermark_key,
    :source_watermark_event_id,
    :organization_id,
    :mission_id,
    :logical_source,
    :data_source_id,
    :source_binding_id,
    :realm,
    :replay_run_id,
    :dataset,
    :event_type,
    :complete_through,
    :previous_complete_through,
    :latest_receipt_time,
    :previous_latest_receipt_time,
    :retention_starts_at,
    :previous_retention_starts_at,
    :sample_count,
    :confidence,
    :reason,
    :observed_at,
    :last_seen_at,
    transition_count: 0,
    payload: %{}
  ]

  @spec from_event(SourceWatermarkEvent.t(), non_neg_integer()) :: t()
  def from_event(%SourceWatermarkEvent{} = event, transition_count \\ 1) do
    %__MODULE__{
      source_watermark_key: event.source_watermark_key,
      source_watermark_event_id: event.source_watermark_event_id,
      organization_id: event.organization_id,
      mission_id: event.mission_id,
      logical_source: event.logical_source,
      data_source_id: event.data_source_id,
      source_binding_id: event.source_binding_id,
      realm: event.realm,
      replay_run_id: event.replay_run_id,
      dataset: event.dataset,
      event_type: event.event_type,
      complete_through: event.complete_through,
      previous_complete_through: event.previous_complete_through,
      latest_receipt_time: event.latest_receipt_time,
      previous_latest_receipt_time: event.previous_latest_receipt_time,
      retention_starts_at: event.retention_starts_at,
      previous_retention_starts_at: event.previous_retention_starts_at,
      sample_count: event.sample_count,
      confidence: event.confidence,
      reason: event.reason,
      observed_at: event.observed_at,
      last_seen_at: event.observed_at,
      transition_count: transition_count,
      payload: event.payload
    }
  end

  @spec to_source_watermark(t(), keyword()) :: SourceWatermark.t()
  def to_source_watermark(%__MODULE__{} = status, opts \\ []) do
    %SourceWatermark{
      logical_source: status.logical_source,
      request_id: Keyword.get(opts, :request_id),
      source_binding_id: status.source_binding_id,
      data_source_id: status.data_source_id,
      realm: status.realm,
      replay_run_id: status.replay_run_id,
      dataset: status.dataset,
      scope: Keyword.get(opts, :scope),
      complete_through: status.complete_through,
      latest_receipt_time: status.latest_receipt_time,
      retention_starts_at: status.retention_starts_at,
      sample_count: status.sample_count,
      confidence: status.confidence,
      meta: %{
        durable_source_watermark?: true,
        source_watermark_event_id: status.source_watermark_event_id,
        source_watermark_observed_at: status.observed_at,
        source_watermark_last_seen_at: status.last_seen_at,
        source_watermark_reason: status.reason
      }
    }
  end
end
