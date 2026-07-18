defmodule Cadence.ContactPlanning.FleetPlanningRunRequirementRef do
  @moduledoc "Exact Requirement input and durable per-Requirement progress for a fleet run."

  alias Cadence.Ids
  alias Cadence.Persistence.JsonDocument

  @input_states [:pending, :searching, :searched, :failed]
  @result_states [:pending, :satisfied, :partial, :unsatisfied, :failed]

  @type t :: %__MODULE__{
          fleet_planning_run_requirement_ref_id: binary(),
          fleet_planning_run_id: binary(),
          organization_id: binary(),
          mission_id: binary(),
          contact_requirement_id: binary(),
          contact_requirement_version: pos_integer(),
          contact_planning_run_id: binary() | nil,
          input_state: atom(),
          result_state: atom(),
          explanation_document: map(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  defstruct [
    :fleet_planning_run_requirement_ref_id,
    :fleet_planning_run_id,
    :organization_id,
    :mission_id,
    :contact_requirement_id,
    :contact_requirement_version,
    :contact_planning_run_id,
    :input_state,
    :result_state,
    :explanation_document,
    :inserted_at,
    :updated_at
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      fleet_planning_run_requirement_ref_id:
        value(
          attrs,
          :fleet_planning_run_requirement_ref_id,
          Ids.new("fleet_run_requirement_ref")
        ),
      fleet_planning_run_id: required(attrs, :fleet_planning_run_id),
      organization_id: required(attrs, :organization_id),
      mission_id: required(attrs, :mission_id),
      contact_requirement_id: required(attrs, :contact_requirement_id),
      contact_requirement_version:
        positive(value(attrs, :contact_requirement_version), :contact_requirement_version),
      contact_planning_run_id: optional_string(value(attrs, :contact_planning_run_id)),
      input_state:
        attrs
        |> value(:input_state, :pending)
        |> atom(@input_states, :input_state),
      result_state:
        attrs
        |> value(:result_state, :pending)
        |> atom(@result_states, :result_state),
      explanation_document:
        document(value(attrs, :explanation_document, %{}), :explanation_document),
      inserted_at: value(attrs, :inserted_at),
      updated_at: value(attrs, :updated_at)
    }
  end

  defp required(attrs, key) do
    case value(attrs, key) do
      item when is_binary(item) and item != "" -> item
      _other -> raise ArgumentError, "#{key} is required"
    end
  end

  defp optional_string(nil), do: nil
  defp optional_string(value) when is_binary(value) and value != "", do: value
  defp optional_string(_value), do: raise(ArgumentError, "planning run id must be non-empty")

  defp positive(value, _field) when is_integer(value) and value > 0, do: value
  defp positive(_value, field), do: raise(ArgumentError, "#{field} must be positive")

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

  defp document(value, _field) when is_map(value), do: JsonDocument.encode(value)
  defp document(_value, field), do: raise(ArgumentError, "#{field} must be an object")

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
