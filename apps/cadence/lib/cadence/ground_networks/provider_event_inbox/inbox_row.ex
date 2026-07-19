defmodule Cadence.GroundNetworks.ProviderEventInbox.InboxRow do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.GroundNetworks.ProviderEventInboxEntry
  alias Cadence.Persistence.{JsonDocument, OrganizationScope}

  @primary_key {:provider_event_inbox_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "provider_event_inbox" do
    field(:organization_id, :string)
    field(:provider_account_id, :string)
    field(:provider_account_version, :integer)
    field(:provider_event_cursor_id, :string)
    field(:environment_ref, :string)
    field(:channel_ref, :string)
    field(:provider_event_id, :string)
    field(:schema_version, :string)
    field(:event_type, :string)
    field(:sequence, :integer)
    field(:resource_type, :string)
    field(:resource_id, :string)
    field(:resource_revision, :integer)
    field(:request_id, :string)
    field(:correlation_id, :string)
    field(:client_reference, :string)
    field(:provider_occurred_at, :utc_datetime_usec)
    field(:received_at, :utc_datetime_usec)
    field(:payload_document, :map)
    field(:content_sha256, :string)
    field(:provider_evidence_id, :string)
    field(:processing_state, :string)
    field(:attempt_count, :integer, default: 0)
    field(:last_attempted_at, :utc_datetime_usec)
    field(:processed_at, :utc_datetime_usec)
    field(:error_document, :map, default: %{})
    field(:identity_collision, :boolean, default: false)
    field(:mission_id, :string)
    field(:provider_id, :string)
    field(:provider_reservation_id, :string)
    field(:scheduled_contact_id, :string)
    field(:contact_id, :string)
    timestamps()
  end

  @immutable_fields [
    :provider_event_inbox_id,
    :organization_id,
    :provider_account_id,
    :provider_account_version,
    :provider_event_cursor_id,
    :environment_ref,
    :channel_ref,
    :provider_event_id,
    :schema_version,
    :event_type,
    :sequence,
    :resource_type,
    :resource_id,
    :resource_revision,
    :request_id,
    :correlation_id,
    :client_reference,
    :provider_occurred_at,
    :received_at,
    :payload_document,
    :content_sha256,
    :provider_evidence_id,
    :identity_collision
  ]

  @processing_fields [
    :processing_state,
    :attempt_count,
    :last_attempted_at,
    :processed_at,
    :error_document,
    :mission_id,
    :provider_id,
    :provider_reservation_id,
    :scheduled_contact_id,
    :contact_id
  ]

  @spec changeset(ProviderEventInboxEntry.t()) :: Ecto.Changeset.t()
  def changeset(%ProviderEventInboxEntry{} = entry) do
    %__MODULE__{}
    |> cast(domain_attrs(entry), @immutable_fields ++ @processing_fields)
    |> OrganizationScope.put_organization_id()
    |> validate_required([
      :provider_event_inbox_id,
      :organization_id,
      :provider_account_id,
      :provider_account_version,
      :environment_ref,
      :channel_ref,
      :provider_event_id,
      :received_at,
      :payload_document,
      :content_sha256,
      :processing_state,
      :error_document
    ])
    |> validate_common()
    |> unique_constraint(
      [
        :organization_id,
        :provider_account_id,
        :provider_account_version,
        :environment_ref,
        :channel_ref,
        :provider_event_id,
        :content_sha256
      ],
      name: :provider_event_inbox_content_identity_idx
    )
  end

  @spec processing_changeset(struct(), map()) :: Ecto.Changeset.t()
  def processing_changeset(%__MODULE__{} = row, attrs) when is_map(attrs) do
    attrs = maybe_wrap_error(attrs)

    row
    |> cast(attrs, @processing_fields)
    |> validate_required([:processing_state, :attempt_count, :error_document])
    |> validate_common()
  end

  @spec to_domain(struct()) :: ProviderEventInboxEntry.t()
  def to_domain(%__MODULE__{} = row) do
    row
    |> Map.from_struct()
    |> Map.take(@immutable_fields ++ @processing_fields)
    |> Map.update!(:payload_document, &JsonDocument.unwrap_value/1)
    |> Map.update!(:error_document, &JsonDocument.unwrap_value/1)
    |> ProviderEventInboxEntry.new()
  end

  defp domain_attrs(entry) do
    entry
    |> Map.from_struct()
    |> Map.take(@immutable_fields ++ @processing_fields)
    |> Map.update!(:processing_state, &Atom.to_string/1)
    |> Map.update!(:payload_document, &JsonDocument.wrap_value/1)
    |> Map.update!(:error_document, &JsonDocument.wrap_value/1)
  end

  defp validate_common(changeset) do
    changeset
    |> validate_number(:provider_account_version, greater_than: 0)
    |> validate_number(:attempt_count, greater_than_or_equal_to: 0)
    |> validate_number(:sequence, greater_than_or_equal_to: 0)
    |> validate_number(:resource_revision, greater_than: 0)
    |> validate_format(:content_sha256, ~r/\A[0-9a-f]{64}\z/)
    |> validate_inclusion(:processing_state, [
      "received",
      "processing",
      "processed",
      "quarantined",
      "reprocessing"
    ])
  end

  defp maybe_wrap_error(attrs) do
    case Map.fetch(attrs, :error_document) do
      {:ok, document} -> Map.put(attrs, :error_document, JsonDocument.wrap_value(document))
      :error -> attrs
    end
  end
end
