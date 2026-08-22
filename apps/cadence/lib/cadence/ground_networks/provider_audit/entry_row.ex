defmodule Cadence.GroundNetworks.ProviderAudit.EntryRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.GroundNetworks.ProviderAuditEntry
  alias Cadence.Persistence.{JsonDocument, OrganizationScope}

  @primary_key {:provider_audit_entry_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "provider_audit_entries" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:provider_account_id, :string)
    field(:provider_account_grant_id, :string)
    field(:provider_id, :string)
    field(:provider_reservation_id, :string)
    field(:provider_change_id, :string)
    field(:contact_id, :string)
    field(:scheduled_contact_id, :string)
    field(:action, :string)
    field(:outcome, :string)
    field(:provider_occurred_at, :utc_datetime_usec)
    field(:recorded_at, :utc_datetime_usec)
    field(:effective_at, :utc_datetime_usec)
    field(:correlation_id, :string)
    field(:request_id, :string)
    field(:client_reference, :string)
    field(:provider_event_id, :string)
    field(:causation_entry_id, :string)
    field(:supersedes_entry_id, :string)
    field(:credential_ref, :string)
    field(:credential_registry_version, :integer)
    field(:credential_backend_version, :string)
    field(:source_document, :map, default: %{})
    field(:actor_document, :map, default: %{})
    field(:previous_document, :map, default: %{})
    field(:current_document, :map, default: %{})
    field(:decision_document, :map, default: %{})
    field(:policy_document, :map, default: %{})
    field(:evidence_references, :map, default: %{})
    field(:metadata, :map, default: %{})

    timestamps()
  end

  @reference_fields [
    :provider_account_id,
    :provider_account_grant_id,
    :provider_id,
    :provider_reservation_id,
    :provider_change_id,
    :contact_id,
    :scheduled_contact_id
  ]

  @document_fields [
    :source_document,
    :actor_document,
    :previous_document,
    :current_document,
    :decision_document,
    :policy_document,
    :evidence_references,
    :metadata
  ]

  @fields [
            :provider_audit_entry_id,
            :organization_id,
            :mission_id,
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
            :credential_backend_version
          ] ++ @reference_fields ++ @document_fields

  @required_fields [
                     :provider_audit_entry_id,
                     :organization_id,
                     :action,
                     :outcome,
                     :recorded_at
                   ] ++ @document_fields

  @audit_document_byte_limit 65_536
  @metadata_byte_limit 16_384

  @spec changeset(ProviderAuditEntry.t()) :: Ecto.Changeset.t()
  def changeset(%ProviderAuditEntry{} = entry) do
    %__MODULE__{}
    |> cast(domain_attrs(entry), @fields)
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
    |> validate_length(:action, min: 1, max: 200)
    |> validate_length(:outcome, min: 1, max: 200)
    |> validate_number(:credential_registry_version, greater_than: 0)
    |> validate_length(:credential_ref, max: 500)
    |> validate_length(:credential_backend_version, max: 500)
    |> validate_document_bounds()
    |> validate_evidence_references()
  end

  @spec to_domain(struct()) :: ProviderAuditEntry.t()
  def to_domain(%__MODULE__{} = row) do
    ProviderAuditEntry.new(%{
      provider_audit_entry_id: row.provider_audit_entry_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      provider_account_id: row.provider_account_id,
      provider_account_grant_id: row.provider_account_grant_id,
      provider_id: row.provider_id,
      provider_reservation_id: row.provider_reservation_id,
      provider_change_id: row.provider_change_id,
      contact_id: row.contact_id,
      scheduled_contact_id: row.scheduled_contact_id,
      action: row.action,
      outcome: row.outcome,
      provider_occurred_at: row.provider_occurred_at,
      recorded_at: row.recorded_at,
      effective_at: row.effective_at,
      correlation_id: row.correlation_id,
      request_id: row.request_id,
      client_reference: row.client_reference,
      provider_event_id: row.provider_event_id,
      causation_entry_id: row.causation_entry_id,
      supersedes_entry_id: row.supersedes_entry_id,
      credential_ref: row.credential_ref,
      credential_registry_version: row.credential_registry_version,
      credential_backend_version: row.credential_backend_version,
      source_document: unwrap(row.source_document),
      actor_document: unwrap(row.actor_document),
      previous_document: unwrap(row.previous_document),
      current_document: unwrap(row.current_document),
      decision_document: unwrap(row.decision_document),
      policy_document: unwrap(row.policy_document),
      evidence_references: JsonDocument.unwrap_items(row.evidence_references),
      metadata: unwrap(row.metadata)
    })
  end

  defp domain_attrs(%ProviderAuditEntry{} = entry) do
    entry
    |> Map.from_struct()
    |> Map.take(@fields)
    |> Map.merge(Map.from_struct(entry.references))
    |> Map.update!(:source_document, &JsonDocument.wrap_value/1)
    |> Map.update!(:actor_document, &JsonDocument.wrap_value/1)
    |> Map.update!(:previous_document, &JsonDocument.wrap_value/1)
    |> Map.update!(:current_document, &JsonDocument.wrap_value/1)
    |> Map.update!(:decision_document, &JsonDocument.wrap_value/1)
    |> Map.update!(:policy_document, &JsonDocument.wrap_value/1)
    |> Map.update!(:evidence_references, &JsonDocument.wrap_items/1)
    |> Map.update!(:metadata, &JsonDocument.wrap_value/1)
  end

  defp unwrap(document), do: JsonDocument.unwrap_value(document)

  defp validate_document_bounds(changeset) do
    changeset =
      Enum.reduce(@document_fields -- [:metadata], changeset, fn field, current ->
        validate_document_bound(current, field, @audit_document_byte_limit)
      end)

    validate_document_bound(changeset, :metadata, @metadata_byte_limit)
  end

  defp validate_document_bound(changeset, field, byte_limit) do
    validate_change(changeset, field, fn ^field, document ->
      case Jason.encode(document) do
        {:ok, json} when byte_size(json) <= byte_limit -> []
        {:ok, _json} -> [{field, "is too large"}]
        {:error, _reason} -> [{field, "must be JSON encodable"}]
      end
    end)
  end

  defp validate_evidence_references(changeset) do
    validate_change(changeset, :evidence_references, fn :evidence_references, document ->
      references = JsonDocument.unwrap_items(document)

      if Enum.all?(references, &valid_evidence_reference?/1),
        do: [],
        else: [evidence_references: "must include evidence IDs and SHA-256 hashes"]
    end)
  end

  defp valid_evidence_reference?(reference) when is_map(reference) do
    evidence_id =
      Map.get(reference, "provider_evidence_id", Map.get(reference, :provider_evidence_id))

    content_sha256 =
      Map.get(reference, "content_sha256", Map.get(reference, :content_sha256))

    is_binary(evidence_id) and evidence_id != "" and is_binary(content_sha256) and
      Regex.match?(~r/\A[0-9a-f]{64}\z/, String.downcase(content_sha256))
  end

  defp valid_evidence_reference?(_reference), do: false
end
