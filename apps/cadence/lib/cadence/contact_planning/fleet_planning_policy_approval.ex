defmodule Cadence.ContactPlanning.FleetPlanningPolicyApproval do
  @moduledoc "Append-only administrator decision on one exact fleet policy version."

  alias Cadence.Ids
  alias Cadence.Persistence.JsonDocument

  @decisions [:approved, :rejected]

  @type t :: %__MODULE__{
          fleet_planning_policy_approval_id: binary(),
          organization_id: binary(),
          mission_id: binary(),
          fleet_planning_policy_id: binary(),
          fleet_planning_policy_version: pos_integer(),
          decision: :approved | :rejected,
          content_sha256: binary(),
          reason: binary(),
          actor_user_id: binary(),
          actor_document: map(),
          decided_at: DateTime.t(),
          inserted_at: DateTime.t() | nil
        }

  defstruct [
    :fleet_planning_policy_approval_id,
    :organization_id,
    :mission_id,
    :fleet_planning_policy_id,
    :fleet_planning_policy_version,
    :decision,
    :content_sha256,
    :reason,
    :actor_user_id,
    :actor_document,
    :decided_at,
    :inserted_at
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      fleet_planning_policy_approval_id:
        value(attrs, :fleet_planning_policy_approval_id, Ids.new("fleet_policy_approval")),
      organization_id: required(attrs, :organization_id),
      mission_id: required(attrs, :mission_id),
      fleet_planning_policy_id: required(attrs, :fleet_planning_policy_id),
      fleet_planning_policy_version:
        positive(value(attrs, :fleet_planning_policy_version), :fleet_planning_policy_version),
      decision:
        attrs
        |> value(:decision)
        |> decision(),
      content_sha256: required(attrs, :content_sha256),
      reason: required(attrs, :reason),
      actor_user_id: required(attrs, :actor_user_id),
      actor_document:
        attrs
        |> value(:actor_document)
        |> document(:actor_document),
      decided_at: datetime(value(attrs, :decided_at, DateTime.utc_now()), :decided_at),
      inserted_at: value(attrs, :inserted_at)
    }
  end

  defp decision(value) when is_atom(value) do
    if value in @decisions,
      do: value,
      else: raise(ArgumentError, "unsupported fleet policy decision")
  end

  defp decision(value) when is_binary(value) do
    Enum.find(@decisions, &(Atom.to_string(&1) == value)) ||
      raise ArgumentError, "unsupported fleet policy decision"
  end

  defp decision(_value), do: raise(ArgumentError, "unsupported fleet policy decision")

  defp required(attrs, key) do
    case value(attrs, key) do
      item when is_binary(item) and item != "" -> item
      _other -> raise ArgumentError, "#{key} is required"
    end
  end

  defp positive(value, _field) when is_integer(value) and value > 0, do: value
  defp positive(_value, field), do: raise(ArgumentError, "#{field} must be positive")

  defp document(value, _field) when is_map(value), do: JsonDocument.encode(value)
  defp document(_value, field), do: raise(ArgumentError, "#{field} must be an object")

  defp datetime(%DateTime{} = value, _field), do: DateTime.truncate(value, :microsecond)
  defp datetime(_value, field), do: raise(ArgumentError, "#{field} must be a timestamp")

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
