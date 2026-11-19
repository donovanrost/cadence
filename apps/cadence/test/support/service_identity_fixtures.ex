defmodule Cadence.ServiceIdentityFixtures do
  @moduledoc """
  An issuer for service identities in tests (#280): every issue and rotation names the person who
  did it, and that person becomes accountable for the identity.
  """

  alias Cadence.Accounts.User
  alias Cadence.Auth.Scope

  @spec issuer_scope(binary(), binary()) :: Scope.t()
  def issuer_scope(organization_id, user_id \\ "user-service-issuer") do
    %Scope{
      actor_kind: :user,
      organization_id: organization_id,
      user: %User{user_id: user_id, display_name: "Service issuer"}
    }
  end
end
