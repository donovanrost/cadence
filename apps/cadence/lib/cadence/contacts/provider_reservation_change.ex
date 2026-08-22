defmodule Cadence.Contacts.ProviderReservationChange do
  @moduledoc "Durable classification and decision state for one provider Contact revision."

  alias Cadence.Ids
  alias Cadence.Persistence.JsonDocument

  @classifications ~w(
    observation policy_accept approval_required acknowledgment_required configuration_failure
  )a
  @lifecycle_states ~w(
    observed pending_approval policy_accepted approved rejected acknowledgment_required
    acknowledged configuration_failure superseded apply_failed
  )a

  @type t :: %__MODULE__{}

  # credo:disable-for-next-line Credo.Check.Warning.StructFieldAmount
  defstruct [
    :provider_reservation_change_id,
    :organization_id,
    :mission_id,
    :provider_reservation_id,
    :provider_account_id,
    :provider_account_version,
    :provider_revision,
    :from_provider_revision,
    :change_identity,
    :proposal_hash,
    :classification,
    :lifecycle_state,
    :policy_version,
    :actionable,
    :already_effective,
    :deadline_at,
    :provider_evidence_id,
    :decided_at,
    :decided_by,
    :inserted_at,
    :updated_at,
    before_snapshot_document: %{},
    after_snapshot_document: %{},
    changed_fields_document: %{},
    policy_document: %{},
    decision_document: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      provider_reservation_change_id:
        value(attrs, :provider_reservation_change_id, Ids.new("provider_change")),
      organization_id: required(attrs, :organization_id),
      mission_id: required(attrs, :mission_id),
      provider_reservation_id: required(attrs, :provider_reservation_id),
      provider_account_id: value(attrs, :provider_account_id),
      provider_account_version: value(attrs, :provider_account_version),
      provider_revision: positive(attrs, :provider_revision),
      from_provider_revision: positive(attrs, :from_provider_revision),
      change_identity: required(attrs, :change_identity),
      proposal_hash: required(attrs, :proposal_hash),
      before_snapshot_document: document(attrs, :before_snapshot_document),
      after_snapshot_document: document(attrs, :after_snapshot_document),
      changed_fields_document: document(attrs, :changed_fields_document),
      classification: member(attrs, :classification, @classifications),
      lifecycle_state: member(attrs, :lifecycle_state, @lifecycle_states),
      policy_version: positive(attrs, :policy_version),
      policy_document: document(attrs, :policy_document),
      decision_document: document(attrs, :decision_document),
      actionable: value(attrs, :actionable, false),
      already_effective: value(attrs, :already_effective, false),
      deadline_at: value(attrs, :deadline_at),
      provider_evidence_id: value(attrs, :provider_evidence_id),
      decided_at: value(attrs, :decided_at),
      decided_by: value(attrs, :decided_by),
      inserted_at: value(attrs, :inserted_at),
      updated_at: value(attrs, :updated_at)
    }
  end

  defp document(attrs, key), do: attrs |> value(key, %{}) |> JsonDocument.encode()

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

  defp member(attrs, key, allowed) do
    case Enum.find(allowed, &(value(attrs, key) in [&1, Atom.to_string(&1)])) do
      nil -> raise ArgumentError, "#{key} is invalid"
      normalized -> normalized
    end
  end

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
