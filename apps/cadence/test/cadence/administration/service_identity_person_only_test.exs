defmodule Cadence.Administration.ServiceIdentityPersonOnlyTest do
  @moduledoc """
  #281: services never manage service identities. Listing, creating, rotating and revoking are a
  person's act (`actor_kind: :user`); a service identity holding `organization_admin` is refused
  before anything is written, so a leaked service token can't mint, re-key or revoke others.
  And whoever issues or rotates holds every capability the identity has.
  """
  use Cadence.DataCase, async: false

  import Ecto.Query

  alias Cadence.Administration.{OrganizationPeople, ServiceIdentityAdministration}
  alias Cadence.Auth
  alias Cadence.Auth.{Policy, Scope, ServiceIdentity, ServiceIdentityRow}

  @org "org-281"

  setup do
    persist_mission_scope(@org, "mission-281")
    {:ok, issued} = issue("Existing automation", [:organization_admin])
    {:ok, service} = Auth.authenticate_api_token(issued.api_token)

    %{
      person: person([:organization_admin]),
      service: service,
      target: issued.service_identity.service_identity_id
    }
  end

  describe "a service identity holding organization_admin is refused" do
    test "its scope really is an organization admin (the hole)", c do
      assert c.service.actor_kind == :service
      assert MapSet.member?(c.service.capabilities, :organization_admin)
    end

    test "on create, and nothing is created", c do
      before = count()

      assert {:error, :authenticated_user_required} =
               ServiceIdentityAdministration.create(c.service, @org, %{
                 "name" => "Minted by a service",
                 "capabilities" => ["organization_admin"]
               })

      assert count() == before
    end

    test "on rotate, and the key is unchanged", c do
      digest = digest(c.target)

      assert {:error, :authenticated_user_required} =
               ServiceIdentityAdministration.rotate(c.service, @org, c.target)

      assert digest(c.target) == digest
    end

    test "on revoke, and the identity stays active", c do
      assert {:error, :authenticated_user_required} =
               ServiceIdentityAdministration.revoke(c.service, @org, c.target)

      assert {:ok, %{lifecycle_state: :active}} = Auth.fetch_service_identity(@org, c.target)
    end

    test "on list", c do
      assert {:error, :authenticated_user_required} =
               OrganizationPeople.service_identities(c.service, @org)
    end

    test "by the policy itself, which the host-action path passes through", c do
      assert {:error, :authenticated_user_required} =
               Policy.authorize(c.service, :manage_service_identities, %{organization_id: @org})

      assert :ok =
               Policy.authorize(c.person, :manage_service_identities, %{organization_id: @org})
    end
  end

  describe "a person who is an organization admin still manages them" do
    test "create, rotate, list and revoke", c do
      assert {:ok, %{service_identity: %{id: id}, api_token: token}} =
               ServiceIdentityAdministration.create(c.person, @org, %{
                 "name" => "Made by a person",
                 "capabilities" => ["organization_admin"]
               })

      assert is_binary(token)

      assert {:ok, %{api_token: rotated}} =
               ServiceIdentityAdministration.rotate(c.person, @org, id)

      assert rotated != token

      assert {:ok, %{service_identities: listed}} =
               OrganizationPeople.service_identities(c.person, @org)

      assert Enum.any?(listed, &(&1.id == id))
      assert :ok = ServiceIdentityAdministration.revoke(c.person, @org, id)
    end
  end

  describe "the actor holds every capability the identity has" do
    test "an organization admin covers both grantable capabilities" do
      assert :ok =
               Policy.ensure_holds_capabilities(person([:organization_admin]), [
                 :organization_admin,
                 :mission_admin
               ])
    end

    test "a platform admin covers any capability" do
      assert :ok =
               Policy.ensure_holds_capabilities(person([:platform_admin]), [
                 :organization_admin,
                 :mission_admin,
                 :platform_admin
               ])
    end

    test "a capability the actor lacks is refused and named" do
      assert {:error, {:capability_beyond_issuer, [:organization_admin]}} =
               Policy.ensure_holds_capabilities(person([:mission_admin]), [
                 :mission_admin,
                 :organization_admin
               ])

      assert {:error, {:capability_beyond_issuer, [:platform_admin]}} =
               Policy.ensure_holds_capabilities(person([:organization_admin]), [:platform_admin])
    end
  end

  defp person(capabilities) do
    %Scope{
      actor_kind: :user,
      organization_id: @org,
      user: %{user_id: "user-281"},
      organization_membership: %{lifecycle_state: :active},
      capabilities: MapSet.new(capabilities)
    }
  end

  defp issue(name, capabilities) do
    Auth.issue_service_identity(
      ServiceIdentity.new(%{
        organization_id: @org,
        display_name: name,
        capabilities: capabilities
      }),
      person([:organization_admin])
    )
  end

  defp count,
    do: Repo.aggregate(from(r in ServiceIdentityRow, where: r.organization_id == ^@org), :count)

  defp digest(id),
    do:
      Repo.one!(
        from(r in ServiceIdentityRow,
          where: r.organization_id == ^@org and r.service_identity_id == ^id,
          select: r.token_digest
        )
      )
end
