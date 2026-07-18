defmodule Cadence.Accounts.OrganizationInvitationRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Accounts.OrganizationInvitation
  alias Cadence.Persistence.JsonDocument

  @primary_key {:organization_invitation_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]
  @required_fields [
    :organization_invitation_id,
    :organization_id,
    :email,
    :membership_role,
    :grant_platform_admin,
    :status,
    :token_digest,
    :token_hint,
    :expires_at,
    :invited_by_user_id,
    :metadata
  ]

  schema "organization_invitations" do
    field(:organization_id, :string)
    field(:email, :string)
    field(:display_name, :string)
    field(:membership_role, :string)
    field(:grant_platform_admin, :boolean, default: false)
    field(:status, :string)
    field(:token_digest, :string)
    field(:token_hint, :string)
    field(:expires_at, :utc_datetime_usec)
    field(:invited_by_user_id, :string)
    field(:accepted_by_user_id, :string)
    field(:accepted_at, :utc_datetime_usec)
    field(:metadata, :map, default: %{})

    timestamps()
  end

  @spec changeset(OrganizationInvitation.t()) :: Ecto.Changeset.t()
  def changeset(%OrganizationInvitation{} = invitation) do
    %__MODULE__{}
    |> cast(row_attrs(invitation), all_fields())
    |> validate_required(@required_fields)
    |> unique_constraint([:token_digest], name: :organization_invitations_token_digest_index)
  end

  @spec update_changeset(struct(), map()) :: Ecto.Changeset.t()
  def update_changeset(%__MODULE__{} = row, attrs) when is_map(attrs) do
    row
    |> cast(attrs, [
      :display_name,
      :membership_role,
      :grant_platform_admin,
      :status,
      :expires_at,
      :accepted_by_user_id,
      :accepted_at,
      :metadata
    ])
    |> validate_required([
      :membership_role,
      :grant_platform_admin,
      :status,
      :expires_at,
      :metadata
    ])
    |> unique_constraint([:token_digest], name: :organization_invitations_token_digest_index)
  end

  @spec to_domain(struct()) :: OrganizationInvitation.t()
  def to_domain(%__MODULE__{} = row) do
    OrganizationInvitation.new(%{
      organization_invitation_id: row.organization_invitation_id,
      organization_id: row.organization_id,
      email: row.email,
      display_name: row.display_name,
      membership_role: row.membership_role,
      grant_platform_admin: row.grant_platform_admin,
      status: row.status,
      token_digest: row.token_digest,
      token_hint: row.token_hint,
      expires_at: row.expires_at,
      invited_by_user_id: row.invited_by_user_id,
      accepted_by_user_id: row.accepted_by_user_id,
      accepted_at: row.accepted_at,
      metadata: JsonDocument.unwrap_value(row.metadata)
    })
  end

  defp row_attrs(%OrganizationInvitation{} = invitation) do
    %{
      organization_invitation_id: invitation.organization_invitation_id,
      organization_id: invitation.organization_id,
      email: invitation.email,
      display_name: invitation.display_name,
      membership_role: Atom.to_string(invitation.membership_role),
      grant_platform_admin: invitation.grant_platform_admin,
      status: Atom.to_string(invitation.status),
      token_digest: invitation.token_digest,
      token_hint: invitation.token_hint,
      expires_at: invitation.expires_at,
      invited_by_user_id: invitation.invited_by_user_id,
      accepted_by_user_id: invitation.accepted_by_user_id,
      accepted_at: invitation.accepted_at,
      metadata: JsonDocument.wrap_value(invitation.metadata)
    }
  end

  defp all_fields do
    [
      :organization_invitation_id,
      :organization_id,
      :email,
      :display_name,
      :membership_role,
      :grant_platform_admin,
      :status,
      :token_digest,
      :token_hint,
      :expires_at,
      :invited_by_user_id,
      :accepted_by_user_id,
      :accepted_at,
      :metadata
    ]
  end
end
