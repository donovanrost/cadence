defmodule Cadence.ContactPlanning.ContactPlanningRun do
  @moduledoc "Durable record of one multi-provider search for an exact Requirement version."

  alias Cadence.Ids

  @states [:running, :completed, :partial, :failed]

  @type lifecycle_state :: :running | :completed | :partial | :failed

  @type t :: %__MODULE__{
          contact_planning_run_id: binary(),
          organization_id: binary(),
          mission_id: binary(),
          contact_requirement_id: binary(),
          contact_requirement_version: pos_integer(),
          lifecycle_state: lifecycle_state(),
          requested_by: binary(),
          started_at: DateTime.t(),
          completed_at: DateTime.t() | nil,
          summary_document: map(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  defstruct [
    :contact_planning_run_id,
    :organization_id,
    :mission_id,
    :contact_requirement_id,
    :contact_requirement_version,
    :lifecycle_state,
    :requested_by,
    :started_at,
    :completed_at,
    :summary_document,
    :inserted_at,
    :updated_at
  ]

  @spec states() :: [lifecycle_state()]
  def states, do: @states

  @spec new(map()) :: t()
  def new(attrs) do
    %__MODULE__{
      contact_planning_run_id: value(attrs, :contact_planning_run_id, Ids.new("planning_run")),
      organization_id: required(attrs, :organization_id),
      mission_id: required(attrs, :mission_id),
      contact_requirement_id: required(attrs, :contact_requirement_id),
      contact_requirement_version:
        positive(value(attrs, :contact_requirement_version), :contact_requirement_version),
      lifecycle_state: normalize_state(value(attrs, :lifecycle_state, :running)),
      requested_by: required(attrs, :requested_by),
      started_at: datetime(value(attrs, :started_at, DateTime.utc_now()), :started_at),
      completed_at: optional_datetime(value(attrs, :completed_at), :completed_at),
      summary_document: document(value(attrs, :summary_document, %{}), :summary_document),
      inserted_at: value(attrs, :inserted_at),
      updated_at: value(attrs, :updated_at)
    }
  end

  defp normalize_state(item) when is_atom(item) do
    if item in @states,
      do: item,
      else: raise(ArgumentError, "unsupported planning run state")
  end

  defp normalize_state(item) when is_binary(item) do
    Enum.find(@states, &(Atom.to_string(&1) == item)) ||
      raise(ArgumentError, "unsupported planning run state")
  end

  defp required(attrs, key) do
    case value(attrs, key) do
      item when is_binary(item) and item != "" -> item
      _other -> raise ArgumentError, "#{key} is required"
    end
  end

  defp positive(item, _field) when is_integer(item) and item > 0, do: item
  defp positive(_item, field), do: raise(ArgumentError, "#{field} must be positive")

  defp datetime(%DateTime{} = item, _field), do: DateTime.truncate(item, :microsecond)
  defp datetime(_item, field), do: raise(ArgumentError, "#{field} must be a timestamp")
  defp optional_datetime(nil, _field), do: nil
  defp optional_datetime(item, field), do: datetime(item, field)

  defp document(item, _field) when is_map(item), do: item
  defp document(_item, field), do: raise(ArgumentError, "#{field} must be an object")

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
