defmodule Cadence.ServiceIdentityFixtures do
  @moduledoc """
  An issuer for service identities in tests (#280): every issue and rotation names the person who
  did it, and that person becomes accountable for the identity.
  """

  import Ecto.Query

  alias Cadence.Accounts.User
  alias Cadence.Auth.{Scope, ServiceAccountableRow}
  alias Cadence.Repo

  @spec issuer_scope(binary(), binary()) :: Scope.t()
  def issuer_scope(organization_id, user_id \\ "user-service-issuer") do
    %Scope{
      actor_kind: :user,
      organization_id: organization_id,
      user: %User{user_id: user_id, display_name: "Service issuer"}
    }
  end

  @doc """
  Makes `service_identity_id` an identity with nobody on record, as one issued before #280.
  The table is append-only (#436), so this uses #116's test-only purge setting, on just for the
  delete and off again, so it can't mask a later write in the same test. Test databases only.
  """
  @spec forget_accountables!(binary()) :: :ok
  def forget_accountables!(service_identity_id) do
    Repo.query!("SET LOCAL cadence.decision_record_test_purge = 'on'")

    Repo.delete_all(
      from(row in ServiceAccountableRow, where: row.service_identity_id == ^service_identity_id)
    )

    Repo.query!("SET LOCAL cadence.decision_record_test_purge = 'off'")
    :ok
  end
end
