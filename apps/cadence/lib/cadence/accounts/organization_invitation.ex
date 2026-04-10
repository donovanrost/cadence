defmodule Cadence.Accounts.OrganizationInvitation do
  @moduledoc """
  Invitation grant for a human to join an organization tenant.
  """

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Ids

  @statuses [:pending, :accepted, :revoked, :expired]

  @type status :: :pending | :accepted | :revoked | :expired

  @type t :: %__MODULE__{
          organization_invitation_id: binary(),
          organization_id: binary(),
          email: binary(),
          display_name: binary() | nil,
          membership_role: OrganizationMembership.role(),
          grant_platform_admin: boolean(),
          status: status(),
          token_digest: binary(),
          token_hint: binary(),
          expires_at: DateTime.t(),
          invited_by_user_id: binary(),
          accepted_by_user_id: binary() | nil,
          accepted_at: DateTime.t() | nil,
          metadata: map()
        }

  defstruct [
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
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      organization_invitation_id:
        Map.get(
          attrs,
          :organization_invitation_id,
          Map.get(attrs, "organization_invitation_id", Ids.new("orginvite"))
        ),
      organization_id: map_fetch!(attrs, :organization_id, "organization_id"),
      email:
        attrs
        |> Map.get(:email, Map.get(attrs, "email"))
        |> User.normalize_email(),
      display_name: Map.get(attrs, :display_name, Map.get(attrs, "display_name")),
      membership_role:
        attrs
        |> Map.get(:membership_role, Map.get(attrs, "membership_role", :member))
        |> OrganizationMembership.normalize_role(),
      grant_platform_admin:
        attrs
        |> Map.get(:grant_platform_admin, Map.get(attrs, "grant_platform_admin", false))
        |> Kernel.==(true),
      status:
        attrs
        |> Map.get(:status, Map.get(attrs, "status", :pending))
        |> normalize_status(),
      token_digest: map_fetch!(attrs, :token_digest, "token_digest"),
      token_hint: map_fetch!(attrs, :token_hint, "token_hint"),
      expires_at: map_fetch!(attrs, :expires_at, "expires_at"),
      invited_by_user_id: map_fetch!(attrs, :invited_by_user_id, "invited_by_user_id"),
      accepted_by_user_id:
        Map.get(attrs, :accepted_by_user_id, Map.get(attrs, "accepted_by_user_id")),
      accepted_at: Map.get(attrs, :accepted_at, Map.get(attrs, "accepted_at")),
      metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
    }
  end

  @spec statuses() :: [status()]
  def statuses, do: @statuses

  @spec normalize_status(status() | binary()) :: status()
  def normalize_status(:pending), do: :pending
  def normalize_status("pending"), do: :pending
  def normalize_status(:accepted), do: :accepted
  def normalize_status("accepted"), do: :accepted
  def normalize_status(:revoked), do: :revoked
  def normalize_status("revoked"), do: :revoked
  def normalize_status(:expired), do: :expired
  def normalize_status("expired"), do: :expired

  @spec pending?(t()) :: boolean()
  def pending?(%__MODULE__{status: :pending}), do: true
  def pending?(%__MODULE__{}), do: false

  @spec expired?(t(), DateTime.t()) :: boolean()
  def expired?(%__MODULE__{expires_at: expires_at}, now \\ DateTime.utc_now()) do
    DateTime.compare(expires_at, now) != :gt
  end

  defp map_fetch!(attrs, atom_key, string_key) when is_map(attrs) do
    case Map.get(attrs, atom_key, Map.get(attrs, string_key)) do
      nil -> raise KeyError, key: atom_key, term: attrs
      value -> value
    end
  end
end
