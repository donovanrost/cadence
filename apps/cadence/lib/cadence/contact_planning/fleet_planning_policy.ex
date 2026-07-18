defmodule Cadence.ContactPlanning.FleetPlanningPolicy do
  @moduledoc "Stable mission-scoped identity and active projection for fleet planning policy."

  alias Cadence.Ids

  @states [:draft, :active, :retired]

  @type lifecycle_state :: :draft | :active | :retired

  @type t :: %__MODULE__{
          fleet_planning_policy_id: binary(),
          organization_id: binary(),
          mission_id: binary(),
          current_version: pos_integer(),
          active_version: pos_integer() | nil,
          lifecycle_state: lifecycle_state(),
          created_by: binary(),
          lifecycle_changed_by: binary(),
          lifecycle_changed_at: DateTime.t(),
          lifecycle_reason: binary(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  defstruct [
    :fleet_planning_policy_id,
    :organization_id,
    :mission_id,
    :current_version,
    :active_version,
    :lifecycle_state,
    :created_by,
    :lifecycle_changed_by,
    :lifecycle_changed_at,
    :lifecycle_reason,
    :inserted_at,
    :updated_at
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    created_by = required(attrs, :created_by)

    %__MODULE__{
      fleet_planning_policy_id:
        value(attrs, :fleet_planning_policy_id, Ids.new("fleet_planning_policy")),
      organization_id: required(attrs, :organization_id),
      mission_id: required(attrs, :mission_id),
      current_version: positive(value(attrs, :current_version, 1), :current_version),
      active_version: optional_positive(value(attrs, :active_version), :active_version),
      lifecycle_state:
        attrs
        |> value(:lifecycle_state, :draft)
        |> atom(@states, :lifecycle_state),
      created_by: created_by,
      lifecycle_changed_by: required(attrs, :lifecycle_changed_by, created_by),
      lifecycle_changed_at:
        datetime(value(attrs, :lifecycle_changed_at, DateTime.utc_now()), :lifecycle_changed_at),
      lifecycle_reason: string(value(attrs, :lifecycle_reason, ""), :lifecycle_reason),
      inserted_at: value(attrs, :inserted_at),
      updated_at: value(attrs, :updated_at)
    }
  end

  defp required(attrs, key, default \\ nil) do
    case value(attrs, key, default) do
      item when is_binary(item) and item != "" -> item
      _other -> raise ArgumentError, "#{key} is required"
    end
  end

  defp positive(value, _field) when is_integer(value) and value > 0, do: value
  defp positive(_value, field), do: raise(ArgumentError, "#{field} must be positive")
  defp optional_positive(nil, _field), do: nil
  defp optional_positive(value, field), do: positive(value, field)

  defp atom(value, allowed, field) when is_atom(value) do
    if value in allowed,
      do: value,
      else: raise(ArgumentError, "unsupported #{field}: #{inspect(value)}")
  end

  defp atom(value, allowed, field) when is_binary(value) do
    Enum.find(allowed, &(Atom.to_string(&1) == value)) ||
      raise ArgumentError, "unsupported #{field}: #{inspect(value)}"
  end

  defp atom(value, _allowed, field),
    do: raise(ArgumentError, "unsupported #{field}: #{inspect(value)}")

  defp datetime(%DateTime{} = value, _field), do: DateTime.truncate(value, :microsecond)
  defp datetime(_value, field), do: raise(ArgumentError, "#{field} must be a timestamp")

  defp string(value, _field) when is_binary(value), do: value
  defp string(_value, field), do: raise(ArgumentError, "#{field} must be a string")

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
