defmodule Cadence.Persistence.Schemas.ActiveLimitDefinitionRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Limits.ActiveDefinition
  alias Cadence.Persistence.JsonDocument

  @primary_key {:definition_activation_key, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "active_limit_definitions" do
    field(:limit_definition_lifecycle_event_id, :string)
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:point_id, :string)
    field(:limit_set_name, :string)
    field(:scope_type, :string)
    field(:scope_ref, :string)
    field(:realm, :string)
    field(:event_type, :string)
    field(:limit_definition_id, :string)
    field(:limit_definition_version, :integer)
    field(:previous_limit_definition_id, :string)
    field(:previous_limit_definition_version, :integer)
    field(:active_from, :utc_datetime_usec)
    field(:active_to, :utc_datetime_usec)
    field(:reason, :string)
    field(:last_seen_at, :utc_datetime_usec)
    field(:transition_count, :integer, default: 1)
    field(:payload, :map, default: %{})

    timestamps()
  end

  @fields [
    :definition_activation_key,
    :limit_definition_lifecycle_event_id,
    :organization_id,
    :mission_id,
    :point_id,
    :limit_set_name,
    :scope_type,
    :scope_ref,
    :realm,
    :event_type,
    :limit_definition_id,
    :limit_definition_version,
    :previous_limit_definition_id,
    :previous_limit_definition_version,
    :active_from,
    :active_to,
    :reason,
    :last_seen_at,
    :transition_count,
    :payload
  ]

  @required_fields [
    :definition_activation_key,
    :limit_definition_lifecycle_event_id,
    :mission_id,
    :point_id,
    :limit_set_name,
    :event_type,
    :limit_definition_id,
    :limit_definition_version,
    :active_from,
    :last_seen_at,
    :transition_count,
    :payload
  ]

  @upsert_fields @fields -- [:definition_activation_key]
  @event_types ["registered", "activated", "superseded", "disabled", "retired", "unknown"]

  @spec changeset(ActiveDefinition.t()) :: Ecto.Changeset.t()
  def changeset(%ActiveDefinition{} = active_definition),
    do: changeset(%__MODULE__{}, active_definition)

  @spec changeset(struct(), ActiveDefinition.t()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = row, %ActiveDefinition{} = active_definition) do
    row
    |> cast(domain_attrs(active_definition), @fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:event_type, @event_types)
    |> validate_number(:limit_definition_version, greater_than: 0)
    |> validate_number(:previous_limit_definition_version, greater_than: 0)
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

  @spec to_domain(struct()) :: ActiveDefinition.t()
  def to_domain(%__MODULE__{} = row) do
    %ActiveDefinition{
      definition_activation_key: row.definition_activation_key,
      limit_definition_lifecycle_event_id: row.limit_definition_lifecycle_event_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      point_id: row.point_id,
      limit_set_name: row.limit_set_name,
      scope_type: maybe_existing_atom(row.scope_type),
      scope_ref: row.scope_ref,
      realm: maybe_existing_atom(row.realm),
      event_type: maybe_existing_atom(row.event_type),
      limit_definition_id: row.limit_definition_id,
      limit_definition_version: row.limit_definition_version,
      previous_limit_definition_id: row.previous_limit_definition_id,
      previous_limit_definition_version: row.previous_limit_definition_version,
      active_from: row.active_from,
      active_to: row.active_to,
      reason: maybe_existing_atom(row.reason),
      last_seen_at: row.last_seen_at,
      transition_count: row.transition_count,
      payload: JsonDocument.unwrap_value(row.payload)
    }
  end

  defp domain_attrs(%ActiveDefinition{} = active_definition) do
    %{
      definition_activation_key: active_definition.definition_activation_key,
      limit_definition_lifecycle_event_id: active_definition.limit_definition_lifecycle_event_id,
      organization_id: active_definition.organization_id,
      mission_id: active_definition.mission_id,
      point_id: active_definition.point_id,
      limit_set_name: active_definition.limit_set_name,
      scope_type: enum_string(active_definition.scope_type),
      scope_ref: active_definition.scope_ref,
      realm: enum_string(active_definition.realm),
      event_type: enum_string(active_definition.event_type),
      limit_definition_id: active_definition.limit_definition_id,
      limit_definition_version: active_definition.limit_definition_version,
      previous_limit_definition_id: active_definition.previous_limit_definition_id,
      previous_limit_definition_version: active_definition.previous_limit_definition_version,
      active_from: active_definition.active_from,
      active_to: active_definition.active_to,
      reason: enum_string(active_definition.reason),
      last_seen_at: active_definition.last_seen_at,
      transition_count: active_definition.transition_count,
      payload: JsonDocument.wrap_value(active_definition.payload)
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
