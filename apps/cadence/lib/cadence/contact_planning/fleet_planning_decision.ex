defmodule Cadence.ContactPlanning.FleetPlanningDecision do
  @moduledoc "Durable explainable optimizer disposition for one considered snapshot."

  alias Cadence.Ids
  alias Cadence.Persistence.JsonDocument

  @dispositions [:selected, :displaced, :ineligible, :locked]

  @type t :: %__MODULE__{
          fleet_planning_decision_id: binary(),
          fleet_planning_run_id: binary(),
          organization_id: binary(),
          mission_id: binary(),
          contact_opportunity_snapshot_id: binary(),
          disposition: atom(),
          score: integer(),
          rank: pos_integer() | nil,
          hard_constraint_document: map(),
          score_document: map(),
          explanation_document: map(),
          inserted_at: DateTime.t() | nil
        }

  defstruct [
    :fleet_planning_decision_id,
    :fleet_planning_run_id,
    :organization_id,
    :mission_id,
    :contact_opportunity_snapshot_id,
    :disposition,
    :score,
    :rank,
    :hard_constraint_document,
    :score_document,
    :explanation_document,
    :inserted_at
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      fleet_planning_decision_id:
        value(attrs, :fleet_planning_decision_id, Ids.new("fleet_planning_decision")),
      fleet_planning_run_id: required(attrs, :fleet_planning_run_id),
      organization_id: required(attrs, :organization_id),
      mission_id: required(attrs, :mission_id),
      contact_opportunity_snapshot_id: required(attrs, :contact_opportunity_snapshot_id),
      disposition:
        attrs
        |> value(:disposition)
        |> atom(@dispositions, :disposition),
      score: integer(value(attrs, :score, 0), :score),
      rank: optional_positive(value(attrs, :rank), :rank),
      hard_constraint_document:
        document(value(attrs, :hard_constraint_document, %{}), :hard_constraint_document),
      score_document: document(value(attrs, :score_document, %{}), :score_document),
      explanation_document:
        document(value(attrs, :explanation_document, %{}), :explanation_document),
      inserted_at: value(attrs, :inserted_at)
    }
  end

  defp required(attrs, key) do
    case value(attrs, key) do
      item when is_binary(item) and item != "" -> item
      _other -> raise ArgumentError, "#{key} is required"
    end
  end

  defp integer(value, _field) when is_integer(value), do: value
  defp integer(_value, field), do: raise(ArgumentError, "#{field} must be an integer")
  defp optional_positive(nil, _field), do: nil
  defp optional_positive(value, _field) when is_integer(value) and value > 0, do: value
  defp optional_positive(_value, field), do: raise(ArgumentError, "#{field} must be positive")

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
