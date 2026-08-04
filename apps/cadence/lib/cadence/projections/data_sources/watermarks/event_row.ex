defmodule Cadence.Projections.DataSources.Watermarks.EventRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.DataSources.SourceWatermarkEvent
  alias Cadence.Persistence.JsonDocument

  @primary_key {:source_watermark_event_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "data_source_watermark_events" do
    field(:source_watermark_key, :string)
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:logical_source, :string)
    field(:data_source_id, :string)
    field(:source_binding_id, :string)
    field(:realm, :string)
    field(:replay_run_id, :string)
    field(:dataset, :string)
    field(:event_type, :string)
    field(:complete_through, :utc_datetime_usec)
    field(:previous_complete_through, :utc_datetime_usec)
    field(:latest_receipt_time, :utc_datetime_usec)
    field(:previous_latest_receipt_time, :utc_datetime_usec)
    field(:retention_starts_at, :utc_datetime_usec)
    field(:previous_retention_starts_at, :utc_datetime_usec)
    field(:sample_count, :integer)
    field(:confidence, :string)
    field(:reason, :string)
    field(:observed_at, :utc_datetime_usec)
    field(:payload, :map, default: %{})

    timestamps()
  end

  @fields [
    :source_watermark_event_id,
    :source_watermark_key,
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
    :payload
  ]

  @required_fields [
    :source_watermark_event_id,
    :source_watermark_key,
    :mission_id,
    :logical_source,
    :data_source_id,
    :event_type,
    :confidence,
    :observed_at,
    :payload
  ]

  @event_types ["observed", "advanced", "retreated", "changed", "unknown"]
  @confidence_values ["authoritative", "best_effort", "unknown"]

  @spec changeset(SourceWatermarkEvent.t()) :: Ecto.Changeset.t()
  def changeset(%SourceWatermarkEvent{} = event) do
    %__MODULE__{}
    |> cast(domain_attrs(event), @fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:event_type, @event_types)
    |> validate_inclusion(:confidence, @confidence_values)
    |> validate_number(:sample_count, greater_than_or_equal_to: 0)
  end

  @spec to_domain(struct()) :: SourceWatermarkEvent.t()
  def to_domain(%__MODULE__{} = row) do
    SourceWatermarkEvent.new(%{
      source_watermark_event_id: row.source_watermark_event_id,
      source_watermark_key: row.source_watermark_key,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      logical_source: maybe_existing_atom(row.logical_source),
      data_source_id: row.data_source_id,
      source_binding_id: row.source_binding_id,
      realm: maybe_existing_atom(row.realm),
      replay_run_id: row.replay_run_id,
      dataset: row.dataset,
      event_type: maybe_existing_atom(row.event_type),
      complete_through: row.complete_through,
      previous_complete_through: row.previous_complete_through,
      latest_receipt_time: row.latest_receipt_time,
      previous_latest_receipt_time: row.previous_latest_receipt_time,
      retention_starts_at: row.retention_starts_at,
      previous_retention_starts_at: row.previous_retention_starts_at,
      sample_count: row.sample_count,
      confidence: maybe_existing_atom(row.confidence),
      reason: maybe_existing_atom(row.reason),
      observed_at: row.observed_at,
      payload: JsonDocument.unwrap_value(row.payload)
    })
  end

  defp domain_attrs(%SourceWatermarkEvent{} = event) do
    %{
      source_watermark_event_id: event.source_watermark_event_id,
      source_watermark_key: event.source_watermark_key,
      organization_id: event.organization_id,
      mission_id: event.mission_id,
      logical_source: enum_string(event.logical_source),
      data_source_id: event.data_source_id,
      source_binding_id: event.source_binding_id,
      realm: enum_string(event.realm),
      replay_run_id: event.replay_run_id,
      dataset: event.dataset,
      event_type: enum_string(event.event_type),
      complete_through: event.complete_through,
      previous_complete_through: event.previous_complete_through,
      latest_receipt_time: event.latest_receipt_time,
      previous_latest_receipt_time: event.previous_latest_receipt_time,
      retention_starts_at: event.retention_starts_at,
      previous_retention_starts_at: event.previous_retention_starts_at,
      sample_count: event.sample_count,
      confidence: enum_string(event.confidence),
      reason: enum_string(event.reason),
      observed_at: event.observed_at,
      payload: JsonDocument.wrap_value(event.payload)
    }
  end

  defp enum_string(nil), do: nil
  defp enum_string(value) when is_atom(value), do: Atom.to_string(value)
  defp enum_string(value), do: value

  defp maybe_existing_atom(nil), do: nil

  defp maybe_existing_atom(value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> value
  end

  defp maybe_existing_atom(value), do: value
end
