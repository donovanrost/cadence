defmodule Cadence.Persistence.Schemas.ScheduledContactRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Contacts.ScheduledContact
  alias Cadence.Persistence.JsonDocument

  @primary_key {:scheduled_contact_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "scheduled_contacts" do
    field(:mission_id, :string)
    field(:organization_id, :string)
    field(:source_endpoint_refs, {:array, :string}, default: [])
    field(:path_template_ids, {:array, :string}, default: [])
    field(:path_template_ref_documents, :map, default: %{})
    field(:path_documents, :map, default: %{})
    field(:starts_at, :utc_datetime_usec)
    field(:ends_at, :utc_datetime_usec)
    field(:provider_contact_ref, :string)
    field(:lifecycle_state, :string)
    field(:realized_contact_id, :string)
    field(:metadata, :map, default: %{})

    timestamps()
  end

  @required_fields [
    :scheduled_contact_id,
    :mission_id,
    :source_endpoint_refs,
    :path_documents,
    :starts_at,
    :lifecycle_state,
    :metadata
  ]

  @spec changeset(ScheduledContact.t()) :: Ecto.Changeset.t()
  def changeset(%ScheduledContact{} = scheduled_contact) do
    %__MODULE__{}
    |> cast(domain_attrs(scheduled_contact), all_fields())
    |> Cadence.Persistence.OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
    |> unique_constraint([:mission_id, :scheduled_contact_id],
      name: :scheduled_contacts_scope_idx
    )
  end

  @spec realized_changeset(struct(), ScheduledContact.t(), Cadence.Contacts.RealizedContact.t()) ::
          Ecto.Changeset.t()
  def realized_changeset(
        %__MODULE__{} = row,
        %ScheduledContact{} = scheduled_contact,
        %Cadence.Contacts.RealizedContact{} = realized_contact
      ) do
    row
    |> change(%{
      lifecycle_state: "realized",
      realized_contact_id: realized_contact.realized_contact_id,
      metadata:
        scheduled_contact.metadata
        |> Map.put(:realized_contact_id, realized_contact.realized_contact_id)
        |> JsonDocument.wrap_value()
    })
  end

  @spec lifecycle_changeset(struct(), atom(), map()) :: Ecto.Changeset.t()
  def lifecycle_changeset(%__MODULE__{} = row, lifecycle_state, metadata_patch)
      when is_atom(lifecycle_state) and is_map(metadata_patch) do
    existing_metadata = JsonDocument.unwrap_value(row.metadata)

    change(row, %{
      lifecycle_state: Atom.to_string(lifecycle_state),
      metadata: existing_metadata |> Map.merge(metadata_patch) |> JsonDocument.wrap_value()
    })
  end

  @spec to_domain(struct()) :: ScheduledContact.t()
  def to_domain(%__MODULE__{} = row) do
    ScheduledContact.new(%{
      scheduled_contact_id: row.scheduled_contact_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      source_endpoint_refs: row.source_endpoint_refs,
      path_template_ids: row.path_template_ids,
      path_template_refs: JsonDocument.unwrap_items(row.path_template_ref_documents),
      paths: JsonDocument.unwrap_items(row.path_documents),
      starts_at: row.starts_at,
      ends_at: row.ends_at,
      provider_contact_ref: row.provider_contact_ref,
      lifecycle_state: row.lifecycle_state,
      realized_contact_id: row.realized_contact_id,
      metadata: JsonDocument.unwrap_value(row.metadata)
    })
  end

  defp domain_attrs(%ScheduledContact{} = scheduled_contact) do
    %{
      scheduled_contact_id: scheduled_contact.scheduled_contact_id,
      organization_id: scheduled_contact.organization_id,
      mission_id: scheduled_contact.mission_id,
      source_endpoint_refs: scheduled_contact.source_endpoint_refs,
      path_template_ids: scheduled_contact.path_template_ids,
      path_template_ref_documents: JsonDocument.wrap_items(scheduled_contact.path_template_refs),
      path_documents: JsonDocument.wrap_items(scheduled_contact.paths),
      starts_at: scheduled_contact.starts_at,
      ends_at: scheduled_contact.ends_at,
      provider_contact_ref: scheduled_contact.provider_contact_ref,
      lifecycle_state: Atom.to_string(scheduled_contact.lifecycle_state),
      realized_contact_id: scheduled_contact.realized_contact_id,
      metadata: JsonDocument.wrap_value(scheduled_contact.metadata)
    }
  end

  defp all_fields do
    [
      :scheduled_contact_id,
      :organization_id,
      :mission_id,
      :source_endpoint_refs,
      :path_template_ids,
      :path_template_ref_documents,
      :path_documents,
      :starts_at,
      :ends_at,
      :provider_contact_ref,
      :lifecycle_state,
      :realized_contact_id,
      :metadata
    ]
  end
end
