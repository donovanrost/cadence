defmodule Cadence.ContactPlanning.ContactPlanExecutionItem do
  @moduledoc "Durable execution state for one approved Contact Plan selection."

  alias Cadence.Ids

  @states [:pending, :requesting, :reserved, :uncertain, :rejected, :failed]

  @type lifecycle_state ::
          :pending | :requesting | :reserved | :uncertain | :rejected | :failed

  @type t :: %__MODULE__{
          contact_plan_execution_item_id: binary(),
          organization_id: binary(),
          mission_id: binary(),
          contact_plan_id: binary(),
          contact_plan_version: pos_integer(),
          contact_opportunity_snapshot_id: binary(),
          idempotency_key: binary(),
          lifecycle_state: lifecycle_state(),
          provider_reservation_id: binary() | nil,
          attempt_count: non_neg_integer(),
          last_error_document: map(),
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  defstruct [
    :contact_plan_execution_item_id,
    :organization_id,
    :mission_id,
    :contact_plan_id,
    :contact_plan_version,
    :contact_opportunity_snapshot_id,
    :idempotency_key,
    :lifecycle_state,
    :provider_reservation_id,
    :attempt_count,
    :last_error_document,
    :started_at,
    :completed_at,
    :inserted_at,
    :updated_at
  ]

  @spec states() :: [lifecycle_state()]
  def states, do: @states

  @spec new(map()) :: t()
  def new(attrs) do
    %__MODULE__{
      contact_plan_execution_item_id:
        value(attrs, :contact_plan_execution_item_id, Ids.new("contact_plan_execution_item")),
      organization_id: required(attrs, :organization_id),
      mission_id: required(attrs, :mission_id),
      contact_plan_id: required(attrs, :contact_plan_id),
      contact_plan_version: positive(value(attrs, :contact_plan_version), :contact_plan_version),
      contact_opportunity_snapshot_id: required(attrs, :contact_opportunity_snapshot_id),
      idempotency_key: required(attrs, :idempotency_key),
      lifecycle_state: state(value(attrs, :lifecycle_state, :pending)),
      provider_reservation_id: optional_string(value(attrs, :provider_reservation_id)),
      attempt_count: nonnegative(value(attrs, :attempt_count, 0), :attempt_count),
      last_error_document: document(value(attrs, :last_error_document, %{})),
      started_at: optional_datetime(value(attrs, :started_at), :started_at),
      completed_at: optional_datetime(value(attrs, :completed_at), :completed_at),
      inserted_at: value(attrs, :inserted_at),
      updated_at: value(attrs, :updated_at)
    }
  end

  defp state(item) when is_atom(item) and item in @states, do: item

  defp state(item) when is_binary(item) do
    Enum.find(@states, &(Atom.to_string(&1) == item)) ||
      raise ArgumentError, "unsupported Contact Plan execution state"
  end

  defp state(_item), do: raise(ArgumentError, "unsupported Contact Plan execution state")

  defp required(attrs, key) do
    case value(attrs, key) do
      item when is_binary(item) and item != "" -> item
      _other -> raise ArgumentError, "#{key} is required"
    end
  end

  defp optional_string(nil), do: nil
  defp optional_string(item) when is_binary(item) and item != "", do: item
  defp optional_string(_item), do: raise(ArgumentError, "reservation reference must be a string")
  defp positive(item, _field) when is_integer(item) and item > 0, do: item
  defp positive(_item, field), do: raise(ArgumentError, "#{field} must be positive")
  defp nonnegative(item, _field) when is_integer(item) and item >= 0, do: item
  defp nonnegative(_item, field), do: raise(ArgumentError, "#{field} must be nonnegative")
  defp document(item) when is_map(item), do: item
  defp document(_item), do: raise(ArgumentError, "last error must be an object")
  defp optional_datetime(nil, _field), do: nil

  defp optional_datetime(%DateTime{} = item, _field),
    do: DateTime.truncate(item, :microsecond)

  defp optional_datetime(_item, field), do: raise(ArgumentError, "#{field} must be a timestamp")

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
