defmodule Cadence.Auth.ServiceIdentityIssuanceTest do
  use Cadence.DataCase, async: false
  alias Cadence.Auth
  alias Cadence.Auth.ServiceIdentity
  alias Cadence.Organizations
  alias Cadence.Organizations.Organization

  test "duplicate issuance returns no token, preserves the original credential and cannot change its tenant" do
    org = organization!("first")
    other = organization!("other")

    identity =
      ServiceIdentity.new(%{
        organization_id: org.organization_id,
        display_name: "Flight automation",
        capabilities: [:organization_admin]
      })

    assert {:ok, original} = Auth.issue_service_identity(identity)
    assert {:ok, first_scope} = Auth.authenticate_api_token(original.api_token)
    assert first_scope.organization_id == org.organization_id
    assert {:error, %Ecto.Changeset{} = duplicate} = Auth.issue_service_identity(identity)
    assert Keyword.has_key?(duplicate.errors, :service_identity_id)

    assert {:error, %Ecto.Changeset{}} =
             Auth.issue_service_identity(%{identity | organization_id: other.organization_id})

    assert {:ok, preserved_scope} = Auth.authenticate_api_token(original.api_token)
    assert preserved_scope.organization_id == org.organization_id
    assert [_] = Auth.list_service_identities(org.organization_id)
    assert Auth.list_service_identities(other.organization_id) == []
  end

  defp organization!(slug) do
    {:ok, org} =
      Organizations.persist_organization(
        Organization.new(%{
          display_name: slug,
          slug: "issuance-#{slug}-#{System.unique_integer([:positive])}"
        })
      )

    org
  end
end
