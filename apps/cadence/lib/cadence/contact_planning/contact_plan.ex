defmodule Cadence.ContactPlanning.ContactPlan do
  @moduledoc "Stable mission-owned Contact Plan identity and current execution projection."

  alias Cadence.Ids

  @states [
    :draft,
    :pending_approval,
    :approved,
    :executing,
    :partially_reserved,
    :reserved,
    :failed,
    :canceled,
    :superseded
  ]

  @type lifecycle_state ::
          :draft
          | :pending_approval
          | :approved
          | :executing
          | :partially_reserved
          | :reserved
          | :failed
          | :canceled
          | :superseded

  @type t :: %__MODULE__{
          contact_plan_id: binary(),
          organization_id: binary(),
          mission_id: binary(),
          current_version: pos_integer(),
          lifecycle_state: lifecycle_state(),
          created_by: binary(),
          lifecycle_changed_by: binary(),
          lifecycle_changed_at: DateTime.t(),
          lifecycle_reason: binary(),
          approved_version: pos_integer() | nil,
          approved_at: DateTime.t() | nil,
          approved_by: binary() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  defstruct [
    :contact_plan_id,
    :organization_id,
    :mission_id,
    :current_version,
    :lifecycle_state,
    :created_by,
    :lifecycle_changed_by,
    :lifecycle_changed_at,
    :lifecycle_reason,
    :approved_version,
    :approved_at,
    :approved_by,
    :inserted_at,
    :updated_at
  ]

  @spec states() :: [lifecycle_state()]
  def states, do: @states

  @spec new(map()) :: t()
  def new(attrs) do
    created_by = required(attrs, :created_by)

    %__MODULE__{
      contact_plan_id: value(attrs, :contact_plan_id, Ids.new("contact_plan")),
      organization_id: required(attrs, :organization_id),
      mission_id: required(attrs, :mission_id),
      current_version: positive(value(attrs, :current_version, 1), :current_version),
      lifecycle_state: normalize_state(value(attrs, :lifecycle_state, :draft)),
      created_by: created_by,
      lifecycle_changed_by: required(attrs, :lifecycle_changed_by, created_by),
      lifecycle_changed_at:
        datetime(value(attrs, :lifecycle_changed_at, DateTime.utc_now()), :lifecycle_changed_at),
      lifecycle_reason: string(value(attrs, :lifecycle_reason, ""), :lifecycle_reason),
      approved_version: optional_positive(value(attrs, :approved_version), :approved_version),
      approved_at: optional_datetime(value(attrs, :approved_at), :approved_at),
      approved_by: optional_string(value(attrs, :approved_by), :approved_by),
      inserted_at: value(attrs, :inserted_at),
      updated_at: value(attrs, :updated_at)
    }
    |> validate_approval_shape()
  end

  defp validate_approval_shape(plan) do
    values = [plan.approved_version, plan.approved_at, plan.approved_by]

    if Enum.all?(values, &is_nil/1) or Enum.all?(values, &(not is_nil(&1))),
      do: plan,
      else: raise(ArgumentError, "plan approval fields must be complete")
  end

  defp normalize_state(item) when is_atom(item) do
    if item in @states,
      do: item,
      else: raise(ArgumentError, "unsupported Contact Plan state")
  end

  defp normalize_state(item) when is_binary(item) do
    Enum.find(@states, &(Atom.to_string(&1) == item)) ||
      raise ArgumentError, "unsupported Contact Plan state"
  end

  defp required(attrs, key, default \\ nil) do
    case value(attrs, key, default) do
      item when is_binary(item) and item != "" -> item
      _other -> raise ArgumentError, "#{key} is required"
    end
  end

  defp optional_string(nil, _field), do: nil
  defp optional_string(item, _field) when is_binary(item) and item != "", do: item
  defp optional_string(_item, field), do: raise(ArgumentError, "#{field} must be a string")
  defp string(item, _field) when is_binary(item), do: item
  defp string(_item, field), do: raise(ArgumentError, "#{field} must be a string")
  defp positive(item, _field) when is_integer(item) and item > 0, do: item
  defp positive(_item, field), do: raise(ArgumentError, "#{field} must be positive")
  defp optional_positive(nil, _field), do: nil
  defp optional_positive(item, field), do: positive(item, field)
  defp datetime(%DateTime{} = item, _field), do: DateTime.truncate(item, :microsecond)
  defp datetime(_item, field), do: raise(ArgumentError, "#{field} must be a timestamp")
  defp optional_datetime(nil, _field), do: nil
  defp optional_datetime(item, field), do: datetime(item, field)

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
