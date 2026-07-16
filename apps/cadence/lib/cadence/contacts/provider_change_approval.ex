defmodule Cadence.Contacts.ProviderChangeApproval do
  @moduledoc "Immutable user decision for one current provider-change proposal."

  alias Cadence.Ids
  alias Cadence.Persistence.JsonDocument

  @decisions ~w(approved rejected acknowledged)a

  @type t :: %__MODULE__{}

  defstruct [
    :provider_change_approval_id,
    :organization_id,
    :mission_id,
    :provider_reservation_change_id,
    :decision,
    :proposal_hash,
    :policy_version,
    :reason,
    :actor_user_id,
    :decided_at,
    :inserted_at,
    actor_document: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      provider_change_approval_id:
        value(attrs, :provider_change_approval_id, Ids.new("provider_change_approval")),
      organization_id: required(attrs, :organization_id),
      mission_id: required(attrs, :mission_id),
      provider_reservation_change_id: required(attrs, :provider_reservation_change_id),
      decision: member(attrs, :decision),
      proposal_hash: required(attrs, :proposal_hash),
      policy_version: positive(attrs, :policy_version),
      reason: required(attrs, :reason),
      actor_user_id: required(attrs, :actor_user_id),
      actor_document: attrs |> value(:actor_document, %{}) |> JsonDocument.encode(),
      decided_at: value(attrs, :decided_at, DateTime.utc_now()),
      inserted_at: value(attrs, :inserted_at)
    }
  end

  defp member(attrs, key) do
    case Enum.find(@decisions, &(value(attrs, key) in [&1, Atom.to_string(&1)])) do
      nil -> raise ArgumentError, "#{key} is invalid"
      normalized -> normalized
    end
  end

  defp required(attrs, key) do
    case value(attrs, key) do
      text when is_binary(text) and text != "" -> text
      _other -> raise ArgumentError, "#{key} is required"
    end
  end

  defp positive(attrs, key) do
    case value(attrs, key) do
      number when is_integer(number) and number > 0 -> number
      _other -> raise ArgumentError, "#{key} must be positive"
    end
  end

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
