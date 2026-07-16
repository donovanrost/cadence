defmodule Cadence.Persistence.Schemas.ScheduledContactRevisionRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Contacts.ScheduledContactRevision
  alias Cadence.Persistence.{JsonDocument, OrganizationScope}

  @primary_key {:scheduled_contact_revision_id, :string, autogenerate: false}

  schema "scheduled_contact_revisions" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:scheduled_contact_id, :string)
    field(:revision, :integer)
    field(:provider_reservation_change_id, :string)
    field(:snapshot_document, :map)
    field(:reason_document, :map)
    field(:created_by, :string)
    field(:created_at, :utc_datetime_usec)
  end

  @fields ~w(
    scheduled_contact_revision_id organization_id mission_id scheduled_contact_id revision
    provider_reservation_change_id snapshot_document reason_document created_by created_at
  )a
  @required @fields -- [:provider_reservation_change_id]

  def changeset(%ScheduledContactRevision{} = revision) do
    %__MODULE__{}
    |> cast(attrs(revision), @fields)
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required)
    |> validate_number(:revision, greater_than: 0)
    |> unique_constraint([:scheduled_contact_id, :revision],
      name: :scheduled_contact_revisions_revision_idx
    )
    |> unique_constraint([:provider_reservation_change_id],
      name: :scheduled_contact_revisions_change_idx
    )
  end

  def to_domain(%__MODULE__{} = row) do
    row
    |> Map.from_struct()
    |> Map.take(@fields)
    |> Map.update!(:snapshot_document, &JsonDocument.unwrap_value/1)
    |> Map.update!(:reason_document, &JsonDocument.unwrap_value/1)
    |> ScheduledContactRevision.new()
  end

  defp attrs(revision) do
    revision
    |> Map.from_struct()
    |> Map.take(@fields)
    |> Map.update!(:snapshot_document, &JsonDocument.wrap_value/1)
    |> Map.update!(:reason_document, &JsonDocument.wrap_value/1)
  end
end
