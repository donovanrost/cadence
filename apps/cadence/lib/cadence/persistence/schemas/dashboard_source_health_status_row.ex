defmodule Cadence.Persistence.Schemas.DashboardSourceHealthStatusRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Dashboards.SourceHealthStatus
  alias Cadence.Persistence.JsonDocument

  @primary_key {:source_health_key, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "dashboard_source_health_statuses" do
    field(:source_health_event_id, :string)
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:logical_source, :string)
    field(:data_source_id, :string)
    field(:source_binding_id, :string)
    field(:realm, :string)
    field(:replay_run_id, :string)
    field(:dataset, :string)
    field(:event_type, :string)
    field(:source_health, :string)
    field(:previous_source_health, :string)
    field(:reason, :string)
    field(:observed_at, :utc_datetime_usec)
    field(:last_seen_at, :utc_datetime_usec)
    field(:transition_count, :integer, default: 1)
    field(:payload, :map, default: %{})

    timestamps()
  end

  @fields [
    :source_health_key,
    :source_health_event_id,
    :organization_id,
    :mission_id,
    :logical_source,
    :data_source_id,
    :source_binding_id,
    :realm,
    :replay_run_id,
    :dataset,
    :event_type,
    :source_health,
    :previous_source_health,
    :reason,
    :observed_at,
    :last_seen_at,
    :transition_count,
    :payload
  ]

  @required_fields [
    :source_health_key,
    :source_health_event_id,
    :mission_id,
    :logical_source,
    :data_source_id,
    :event_type,
    :source_health,
    :observed_at,
    :last_seen_at,
    :transition_count,
    :payload
  ]

  @upsert_fields @fields -- [:source_health_key]
  @source_health_values ["healthy", "degraded", "unavailable", "unknown"]
  @event_types ["degraded", "recovered", "unavailable", "unknown"]

  @spec changeset(SourceHealthStatus.t()) :: Ecto.Changeset.t()
  def changeset(%SourceHealthStatus{} = status), do: changeset(%__MODULE__{}, status)

  @spec changeset(struct(), SourceHealthStatus.t()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = row, %SourceHealthStatus{} = status) do
    row
    |> cast(domain_attrs(status), @fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:source_health, @source_health_values)
    |> validate_inclusion(:previous_source_health, @source_health_values)
    |> validate_inclusion(:event_type, @event_types)
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

  @spec to_domain(struct()) :: SourceHealthStatus.t()
  def to_domain(%__MODULE__{} = row) do
    %SourceHealthStatus{
      source_health_key: row.source_health_key,
      source_health_event_id: row.source_health_event_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      logical_source: maybe_existing_atom(row.logical_source),
      data_source_id: row.data_source_id,
      source_binding_id: row.source_binding_id,
      realm: maybe_existing_atom(row.realm),
      replay_run_id: row.replay_run_id,
      dataset: row.dataset,
      event_type: maybe_existing_atom(row.event_type),
      source_health: maybe_existing_atom(row.source_health),
      previous_source_health: maybe_existing_atom(row.previous_source_health),
      reason: maybe_existing_atom(row.reason),
      observed_at: row.observed_at,
      last_seen_at: row.last_seen_at,
      transition_count: row.transition_count,
      payload: JsonDocument.unwrap_value(row.payload)
    }
  end

  defp domain_attrs(%SourceHealthStatus{} = status) do
    %{
      source_health_key: status.source_health_key,
      source_health_event_id: status.source_health_event_id,
      organization_id: status.organization_id,
      mission_id: status.mission_id,
      logical_source: enum_string(status.logical_source),
      data_source_id: status.data_source_id,
      source_binding_id: status.source_binding_id,
      realm: enum_string(status.realm),
      replay_run_id: status.replay_run_id,
      dataset: status.dataset,
      event_type: enum_string(status.event_type),
      source_health: enum_string(status.source_health),
      previous_source_health: enum_string(status.previous_source_health),
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
