defmodule Cadence.Contacts.ProviderReservation do
  @moduledoc """
  Durable evidence and lifecycle state for one external provider reservation attempt.

  A reservation exists before Cadence mutates provider state. The preallocated
  Scheduled Contact ID and immutable route snapshot let reconciliation safely
  converge an ambiguous provider response after a process restart.
  """

  alias Cadence.Contacts.KnownAtom
  alias Cadence.Ids
  alias Cadence.Persistence.JsonDocument

  @type lifecycle_state ::
          :requesting
          | :pending
          | :confirmed
          | :active
          | :completed
          | :unknown
          | :rejected
          | :canceling
          | :canceled
          | :failed

  @type t :: %__MODULE__{
          provider_reservation_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          provider_profile_id: binary(),
          provider_profile_version: pos_integer(),
          scheduled_contact_id: binary(),
          provider_opportunity_ref: binary(),
          provider_contact_ref: binary() | nil,
          idempotency_key: binary(),
          lifecycle_state: lifecycle_state(),
          provider_status: binary() | nil,
          spacecraft_id: binary(),
          provider_spacecraft_ref: binary(),
          source_endpoint_refs: [binary()],
          path_template_ids: [binary()],
          starts_at: DateTime.t(),
          ends_at: DateTime.t(),
          request_document: map(),
          response_document: map(),
          last_error_document: map(),
          attempt_count: non_neg_integer(),
          last_reconciled_at: DateTime.t() | nil,
          metadata: map(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  defstruct [
    :provider_reservation_id,
    :organization_id,
    :mission_id,
    :provider_profile_id,
    :provider_profile_version,
    :scheduled_contact_id,
    :provider_opportunity_ref,
    :provider_contact_ref,
    :idempotency_key,
    :lifecycle_state,
    :provider_status,
    :spacecraft_id,
    :provider_spacecraft_ref,
    :starts_at,
    :ends_at,
    :last_reconciled_at,
    :inserted_at,
    :updated_at,
    source_endpoint_refs: [],
    path_template_ids: [],
    request_document: %{},
    response_document: %{},
    last_error_document: %{},
    attempt_count: 0,
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      provider_reservation_id:
        get(attrs, :provider_reservation_id, Ids.new("provider_reservation")),
      organization_id: get(attrs, :organization_id),
      mission_id: fetch!(attrs, :mission_id),
      provider_profile_id: fetch!(attrs, :provider_profile_id),
      provider_profile_version: get(attrs, :provider_profile_version, 1),
      scheduled_contact_id: get(attrs, :scheduled_contact_id, Ids.new("scheduled_contact")),
      provider_opportunity_ref: fetch!(attrs, :provider_opportunity_ref),
      provider_contact_ref: get(attrs, :provider_contact_ref),
      idempotency_key: fetch!(attrs, :idempotency_key),
      lifecycle_state:
        attrs
        |> get(:lifecycle_state, :requesting)
        |> KnownAtom.provider_reservation_lifecycle_state!(),
      provider_status: get(attrs, :provider_status),
      spacecraft_id: fetch!(attrs, :spacecraft_id),
      provider_spacecraft_ref: fetch!(attrs, :provider_spacecraft_ref),
      source_endpoint_refs: get(attrs, :source_endpoint_refs, []),
      path_template_ids: get(attrs, :path_template_ids, []),
      starts_at: fetch!(attrs, :starts_at),
      ends_at: fetch!(attrs, :ends_at),
      request_document: attrs |> get(:request_document, %{}) |> JsonDocument.encode(),
      response_document: attrs |> get(:response_document, %{}) |> JsonDocument.encode(),
      last_error_document: attrs |> get(:last_error_document, %{}) |> JsonDocument.encode(),
      attempt_count: get(attrs, :attempt_count, 0),
      last_reconciled_at: get(attrs, :last_reconciled_at),
      metadata: attrs |> get(:metadata, %{}) |> JsonDocument.encode(),
      inserted_at: get(attrs, :inserted_at),
      updated_at: get(attrs, :updated_at)
    }
  end

  defp get(attrs, key, default \\ nil) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
  end

  defp fetch!(attrs, key) do
    case get(attrs, key) do
      nil -> raise KeyError, key: key, term: attrs
      value -> value
    end
  end
end
