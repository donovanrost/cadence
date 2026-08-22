defmodule Cadence.ContactPlanning.ContactRequirement do
  @moduledoc "Stable mission-owned Contact Requirement identity and current projection."

  alias Cadence.Ids

  @lifecycle_states [:active, :closed, :canceled]

  @type lifecycle_state :: :active | :closed | :canceled

  @type t :: %__MODULE__{
          contact_requirement_id: binary(),
          organization_id: binary(),
          mission_id: binary(),
          current_version: pos_integer(),
          lifecycle_state: lifecycle_state(),
          created_by: binary(),
          lifecycle_changed_by: binary(),
          lifecycle_changed_at: DateTime.t(),
          lifecycle_reason: binary(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  defstruct [
    :contact_requirement_id,
    :organization_id,
    :mission_id,
    :current_version,
    :lifecycle_state,
    :created_by,
    :lifecycle_changed_by,
    :lifecycle_changed_at,
    :lifecycle_reason,
    :inserted_at,
    :updated_at
  ]

  @spec lifecycle_states() :: [lifecycle_state()]
  def lifecycle_states, do: @lifecycle_states

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      contact_requirement_id:
        value(attrs, :contact_requirement_id, Ids.new("contact_requirement")),
      organization_id: required(attrs, :organization_id),
      mission_id: required(attrs, :mission_id),
      current_version: positive_integer(value(attrs, :current_version, 1), :current_version),
      lifecycle_state:
        attrs
        |> value(:lifecycle_state, :active)
        |> normalize_atom(@lifecycle_states, :lifecycle_state),
      created_by: required(attrs, :created_by),
      lifecycle_changed_by: required(attrs, :lifecycle_changed_by, value(attrs, :created_by)),
      lifecycle_changed_at:
        datetime(value(attrs, :lifecycle_changed_at, DateTime.utc_now()), :lifecycle_changed_at),
      lifecycle_reason: value(attrs, :lifecycle_reason, ""),
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

  defp positive_integer(item, _field) when is_integer(item) and item > 0, do: item
  defp positive_integer(_item, field), do: raise(ArgumentError, "#{field} must be positive")

  defp normalize_atom(item, allowed, field) when is_atom(item) do
    if item in allowed,
      do: item,
      else: raise(ArgumentError, "unsupported #{field}: #{inspect(item)}")
  end

  defp normalize_atom(item, allowed, field) when is_binary(item) do
    Enum.find(allowed, &(Atom.to_string(&1) == item)) ||
      raise ArgumentError, "unsupported #{field}: #{inspect(item)}"
  end

  defp normalize_atom(item, _allowed, field),
    do: raise(ArgumentError, "unsupported #{field}: #{inspect(item)}")

  defp datetime(%DateTime{} = item, _field), do: DateTime.truncate(item, :microsecond)
  defp datetime(_item, field), do: raise(ArgumentError, "#{field} must be a timestamp")

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
