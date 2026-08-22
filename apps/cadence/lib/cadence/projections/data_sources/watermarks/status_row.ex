defmodule Cadence.Projections.DataSources.Watermarks.StatusRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.DataSources.SourceWatermarkStatus
  alias Cadence.Persistence.JsonDocument

  @primary_key {:source_watermark_key, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "data_source_watermark_statuses" do
    field(:source_watermark_event_id, :string)
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
    field(:last_seen_at, :utc_datetime_usec)
    field(:transition_count, :integer, default: 1)
    field(:payload, :map, default: %{})

    timestamps()
  end

  @fields [
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
    :transition_count,
    :payload
  ]

  @required_fields [
    :source_watermark_key,
    :source_watermark_event_id,
    :mission_id,
    :logical_source,
    :data_source_id,
    :event_type,
    :confidence,
    :observed_at,
    :last_seen_at,
    :transition_count,
    :payload
  ]

  @upsert_fields @fields -- [:source_watermark_key]
  @event_types ["observed", "advanced", "retreated", "changed", "unknown"]
  @confidence_values ["authoritative", "best_effort", "unknown"]

  @spec changeset(SourceWatermarkStatus.t()) :: Ecto.Changeset.t()
  def changeset(%SourceWatermarkStatus{} = status), do: changeset(%__MODULE__{}, status)

  @spec changeset(struct(), SourceWatermarkStatus.t()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = row, %SourceWatermarkStatus{} = status) do
    row
    |> cast(domain_attrs(status), @fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:event_type, @event_types)
    |> validate_inclusion(:confidence, @confidence_values)
    |> validate_number(:sample_count, greater_than_or_equal_to: 0)
    |> validate_number(:transition_count, greater_than_or_equal_to: 0)
  end

  @spec touch_changeset(struct(), DateTime.t(), map()) :: Ecto.Changeset.t()
  def touch_changeset(%__MODULE__{} = row, %DateTime{} = observed_at, payload)
      when is_map(payload) do
    last_seen_at =
      case row.last_seen_at do
        %DateTime{} = current ->
          if DateTime.compare(observed_at, current) == :lt, do: current, else: observed_at

        _other ->
          observed_at
      end

    row
    |> change(%{last_seen_at: truncate_datetime(last_seen_at)})
    |> put_change(:payload, JsonDocument.wrap_value(payload))
  end

  @spec upsert_fields() :: [atom()]
  def upsert_fields, do: @upsert_fields

  @spec to_domain(struct()) :: SourceWatermarkStatus.t()
  def to_domain(%__MODULE__{} = row) do
    %SourceWatermarkStatus{
      source_watermark_key: row.source_watermark_key,
      source_watermark_event_id: row.source_watermark_event_id,
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
      last_seen_at: row.last_seen_at,
      transition_count: row.transition_count,
      payload: JsonDocument.unwrap_value(row.payload)
    }
  end

  defp domain_attrs(%SourceWatermarkStatus{} = status) do
    %{
      source_watermark_key: status.source_watermark_key,
      source_watermark_event_id: status.source_watermark_event_id,
      organization_id: status.organization_id,
      mission_id: status.mission_id,
      logical_source: enum_string(status.logical_source),
      data_source_id: status.data_source_id,
      source_binding_id: status.source_binding_id,
      realm: enum_string(status.realm),
      replay_run_id: status.replay_run_id,
      dataset: status.dataset,
      event_type: enum_string(status.event_type),
      complete_through: status.complete_through,
      previous_complete_through: status.previous_complete_through,
      latest_receipt_time: status.latest_receipt_time,
      previous_latest_receipt_time: status.previous_latest_receipt_time,
      retention_starts_at: status.retention_starts_at,
      previous_retention_starts_at: status.previous_retention_starts_at,
      sample_count: status.sample_count,
      confidence: enum_string(status.confidence),
      reason: enum_string(status.reason),
      observed_at: status.observed_at,
      last_seen_at: status.last_seen_at,
      transition_count: status.transition_count,
      payload: JsonDocument.wrap_value(status.payload)
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

  defp truncate_datetime(%DateTime{} = datetime) do
    datetime = DateTime.truncate(datetime, :microsecond)
    {microsecond, _precision} = datetime.microsecond
    %{datetime | microsecond: {microsecond, 6}}
  end
end
