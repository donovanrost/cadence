defmodule Cadence.Contacts.ContactStore.ContactActionRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Contacts.ContactAction
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Persistence.OrganizationScope

  @primary_key {:contact_action_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "contact_actions" do
    field(:mission_id, :string)
    field(:organization_id, :string)
    field(:scheduled_contact_id, :string)
    field(:realized_contact_id, :string)
    field(:action_kind, :string)
    field(:reason, :string)
    field(:actor_document, :map, default: %{})
    field(:metadata_document, :map, default: %{})
    field(:occurred_at, :utc_datetime_usec)

    timestamps()
  end

  @required_fields [
    :contact_action_id,
    :mission_id,
    :action_kind,
    :actor_document,
    :metadata_document,
    :occurred_at
  ]

  @spec changeset(ContactAction.t()) :: Ecto.Changeset.t()
  def changeset(%ContactAction{} = contact_action) do
    %__MODULE__{}
    |> cast(domain_attrs(contact_action), all_fields())
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
    |> unique_constraint([:mission_id, :contact_action_id], name: :contact_actions_scope_idx)
  end

  @spec to_domain(struct()) :: ContactAction.t()
  def to_domain(%__MODULE__{} = row) do
    ContactAction.new(%{
      contact_action_id: row.contact_action_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      scheduled_contact_id: row.scheduled_contact_id,
      realized_contact_id: row.realized_contact_id,
      action_kind: row.action_kind,
      reason: row.reason,
      actor: JsonDocument.unwrap_value(row.actor_document),
      metadata: JsonDocument.unwrap_value(row.metadata_document),
      occurred_at: row.occurred_at
    })
  end

  defp domain_attrs(%ContactAction{} = contact_action) do
    %{
      contact_action_id: contact_action.contact_action_id,
      organization_id: contact_action.organization_id,
      mission_id: contact_action.mission_id,
      scheduled_contact_id: contact_action.scheduled_contact_id,
      realized_contact_id: contact_action.realized_contact_id,
      action_kind: Atom.to_string(contact_action.action_kind),
      reason: contact_action.reason,
      actor_document: JsonDocument.wrap_value(contact_action.actor),
      metadata_document: JsonDocument.wrap_value(contact_action.metadata),
      occurred_at: contact_action.occurred_at
    }
  end

  defp all_fields do
    [
      :contact_action_id,
      :organization_id,
      :mission_id,
      :scheduled_contact_id,
      :realized_contact_id,
      :action_kind,
      :reason,
      :actor_document,
      :metadata_document,
      :occurred_at
    ]
  end
end
