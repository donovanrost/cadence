defmodule Cadence.Persistence.Schemas.RealizedContactRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Contacts.RealizedContact
  alias Cadence.Persistence.JsonDocument

  @primary_key {:realized_contact_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "realized_contacts" do
    field(:mission_id, :string)
    field(:organization_id, :string)
    field(:scheduled_contact_id, :string)
    field(:source_endpoint_refs, {:array, :string}, default: [])
    field(:path_documents, :map, default: %{})
    field(:clock_mode, :string)
    field(:initial_time, :utc_datetime_usec)
    field(:lifecycle_state, :string)
    field(:realized_at, :utc_datetime_usec)
    field(:metadata, :map, default: %{})

    timestamps()
  end

  @required_fields [
    :realized_contact_id,
    :mission_id,
    :source_endpoint_refs,
    :path_documents,
    :clock_mode,
    :lifecycle_state,
    :metadata
  ]

  @spec changeset(RealizedContact.t()) :: Ecto.Changeset.t()
  def changeset(%RealizedContact{} = realized_contact) do
    %__MODULE__{}
    |> cast(domain_attrs(realized_contact), all_fields())
    |> Cadence.Persistence.OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
    |> unique_constraint([:mission_id, :realized_contact_id],
      name: :realized_contacts_scope_idx
    )
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

  @spec to_domain(struct()) :: RealizedContact.t()
  def to_domain(%__MODULE__{} = row) do
    RealizedContact.new(%{
      realized_contact_id: row.realized_contact_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      scheduled_contact_id: row.scheduled_contact_id,
      source_endpoint_refs: row.source_endpoint_refs,
      paths: JsonDocument.unwrap_items(row.path_documents),
      clock_mode: row.clock_mode,
      initial_time: row.initial_time,
      lifecycle_state: row.lifecycle_state,
      realized_at: row.realized_at,
      metadata: JsonDocument.unwrap_value(row.metadata)
    })
  end

  defp domain_attrs(%RealizedContact{} = realized_contact) do
    %{
      realized_contact_id: realized_contact.realized_contact_id,
      organization_id: realized_contact.organization_id,
      mission_id: realized_contact.mission_id,
      scheduled_contact_id: realized_contact.scheduled_contact_id,
      source_endpoint_refs: realized_contact.source_endpoint_refs,
      path_documents: JsonDocument.wrap_items(realized_contact.paths),
      clock_mode: Atom.to_string(realized_contact.clock_mode),
      initial_time: realized_contact.initial_time,
      lifecycle_state: Atom.to_string(realized_contact.lifecycle_state),
      realized_at: realized_contact.realized_at,
      metadata: JsonDocument.wrap_value(realized_contact.metadata)
    }
  end

  defp all_fields do
    [
      :realized_contact_id,
      :organization_id,
      :mission_id,
      :scheduled_contact_id,
      :source_endpoint_refs,
      :path_documents,
      :clock_mode,
      :initial_time,
      :lifecycle_state,
      :realized_at,
      :metadata
    ]
  end
end
