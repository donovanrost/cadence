defmodule Cadence.GroundNetworks.ProviderAuditEntry do
  @moduledoc "Append-only record of a provider interaction or Cadence decision."

  alias Cadence.GroundNetworks.{ProviderAuditReferences, Validation}
  alias Cadence.Ids
  alias Cadence.Persistence.JsonDocument

  @type t :: %__MODULE__{
          provider_audit_entry_id: binary(),
          organization_id: binary(),
          mission_id: binary() | nil,
          references: ProviderAuditReferences.t(),
          action: binary(),
          outcome: binary(),
          provider_occurred_at: DateTime.t() | nil,
          recorded_at: DateTime.t(),
          effective_at: DateTime.t() | nil,
          correlation_id: binary() | nil,
          request_id: binary() | nil,
          client_reference: binary() | nil,
          provider_event_id: binary() | nil,
          causation_entry_id: binary() | nil,
          supersedes_entry_id: binary() | nil,
          credential_ref: binary() | nil,
          credential_registry_version: pos_integer() | nil,
          credential_backend_version: binary() | nil,
          source_document: map(),
          actor_document: map(),
          previous_document: map(),
          current_document: map(),
          decision_document: map(),
          policy_document: map(),
          evidence_references: [map()],
          metadata: map()
        }

  defstruct [
    :provider_audit_entry_id,
    :organization_id,
    :mission_id,
    :references,
    :action,
    :outcome,
    :provider_occurred_at,
    :recorded_at,
    :effective_at,
    :correlation_id,
    :request_id,
    :client_reference,
    :provider_event_id,
    :causation_entry_id,
    :supersedes_entry_id,
    :credential_ref,
    :credential_registry_version,
    :credential_backend_version,
    source_document: %{},
    actor_document: %{},
    previous_document: %{},
    current_document: %{},
    decision_document: %{},
    policy_document: %{},
    evidence_references: [],
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    organization_id = required(attrs, :organization_id)
    action = required(attrs, :action)
    outcome = required(attrs, :outcome)

    base = %__MODULE__{
      provider_audit_entry_id:
        value(attrs, :provider_audit_entry_id, Ids.new("provider_audit_entry")),
      organization_id: organization_id,
      mission_id: optional_text(attrs, :mission_id),
      references: ProviderAuditReferences.new(attrs),
      action: action,
      outcome: outcome,
      provider_occurred_at: value(attrs, :provider_occurred_at),
      recorded_at: value(attrs, :recorded_at, DateTime.utc_now()),
      effective_at: value(attrs, :effective_at),
      correlation_id: optional_text(attrs, :correlation_id),
      request_id: optional_text(attrs, :request_id),
      client_reference: optional_text(attrs, :client_reference),
      provider_event_id: optional_text(attrs, :provider_event_id),
      causation_entry_id: optional_text(attrs, :causation_entry_id),
      supersedes_entry_id: optional_text(attrs, :supersedes_entry_id),
      credential_ref: optional_text(attrs, :credential_ref),
      credential_registry_version: value(attrs, :credential_registry_version),
      credential_backend_version: optional_text(attrs, :credential_backend_version),
      source_document: document(attrs, :source_document),
      actor_document: document(attrs, :actor_document),
      previous_document: document(attrs, :previous_document),
      current_document: document(attrs, :current_document),
      decision_document: document(attrs, :decision_document),
      policy_document: document(attrs, :policy_document),
      evidence_references: evidence_references(attrs),
      metadata: document(attrs, :metadata)
    }

    base
  end

  defp evidence_references(attrs) do
    case value(attrs, :evidence_references, []) do
      references when is_list(references) ->
        Enum.map(references, fn
          reference when is_map(reference) ->
            reference
            |> JsonDocument.encode()
            |> Validation.sanitize()

          _other ->
            raise ArgumentError, "evidence_references must contain maps"
        end)

      _other ->
        raise ArgumentError, "evidence_references must be a list"
    end
  end

  defp document(attrs, key) do
    case value(attrs, key, %{}) do
      document when is_map(document) -> Validation.sanitize(document)
      _other -> raise ArgumentError, "#{key} must be a map"
    end
  end

  defp required(attrs, key) do
    case value(attrs, key) do
      value when is_binary(value) and value != "" -> value
      _other -> raise ArgumentError, "#{key} is required"
    end
  end

  defp optional_text(attrs, key) do
    case value(attrs, key) do
      nil -> nil
      value when is_binary(value) and value != "" -> value
      _other -> raise ArgumentError, "#{key} must be non-empty text"
    end
  end

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
