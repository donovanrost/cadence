defmodule Cadence.Persistence.Schemas.ProviderChangeApprovalRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Contacts.ProviderChangeApproval
  alias Cadence.Persistence.{JsonDocument, OrganizationScope}

  @primary_key {:provider_change_approval_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "provider_change_approvals" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:provider_reservation_change_id, :string)
    field(:decision, :string)
    field(:proposal_hash, :string)
    field(:policy_version, :integer)
    field(:reason, :string)
    field(:actor_user_id, :string)
    field(:actor_document, :map)
    field(:decided_at, :utc_datetime_usec)
    timestamps()
  end

  @fields ~w(
    provider_change_approval_id organization_id mission_id provider_reservation_change_id
    decision proposal_hash policy_version reason actor_user_id actor_document decided_at inserted_at
  )a
  @required @fields -- [:inserted_at]

  def changeset(%ProviderChangeApproval{} = approval) do
    %__MODULE__{}
    |> cast(attrs(approval), @fields)
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required)
    |> validate_number(:policy_version, greater_than: 0)
    |> unique_constraint([:provider_reservation_change_id],
      name: :provider_change_approvals_change_idx
    )
  end

  def to_domain(%__MODULE__{} = row) do
    row
    |> Map.from_struct()
    |> Map.take(@fields)
    |> Map.update!(:actor_document, &JsonDocument.unwrap_value/1)
    |> ProviderChangeApproval.new()
  end

  defp attrs(approval) do
    approval
    |> Map.from_struct()
    |> Map.take(@fields)
    |> Map.update!(:decision, &Atom.to_string/1)
    |> Map.update!(:actor_document, &JsonDocument.wrap_value/1)
  end
end
