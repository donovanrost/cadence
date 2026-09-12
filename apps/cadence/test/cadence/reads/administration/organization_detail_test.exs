defmodule Cadence.Reads.Administration.OrganizationDetailTest do
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.{
    OrganizationInvitation,
    OrganizationInvitationRow,
    OrganizationMembership,
    OrganizationMembershipRow,
    User,
    UserRow
  }

  alias Cadence.Administration.{OrganizationInvitations, ServiceIdentityIssuance}
  alias Cadence.Auth
  alias Cadence.Auth.{Scope, ServiceIdentity}
  alias Cadence.Organizations
  alias Cadence.Organizations.Organization
  alias Cadence.Reads.Administration.OrganizationDetail

  setup do
    user = user!("administrator", [:platform_admin])
    org = organization!("owned")
    other = organization!("other")
    %{scope: Scope.new(%{user: user, admin_mode?: true}), user: user, org: org, other: other}
  end

  test "three independently bounded pages exclude foreign rows and credential material", c do
    for i <- 1..28 do
      id = String.pad_leading(to_string(i), 3, "0")
      member!(c.org, "member-#{id}", if(i == 1, do: :disabled, else: :active))
      invitation!(c.org, "invite-#{id}", c.user)
      service!(c.org, "svc-#{id}")
    end

    member!(c.other, "foreign-member")
    invitation!(c.other, "foreign-invite", c.user)
    service!(c.other, "foreign-service")
    invitation!(c.org, "expired-invite", c.user, :pending, DateTime.add(DateTime.utc_now(), -60))
    invitation!(c.org, "revoked-invite", c.user, :revoked)
    assert {:ok, first} = OrganizationDetail.load(c.scope, c.org.organization_id)

    for key <- ~w(members invitations services) do
      assert length(first[key]["entries"]) == 25
      assert first[key]["next_after"] == List.last(first[key]["entries"])["id"]
    end

    assert hd(first["members"]["entries"])["user_state"] == "disabled"

    assert {:ok, last} =
             OrganizationDetail.load(c.scope, c.org.organization_id, %{
               "members_after" => first["members"]["next_after"],
               "invitations_after" => first["invitations"]["next_after"],
               "services_after" => first["services"]["next_after"]
             })

    for key <- ~w(members invitations services) do
      assert length(last[key]["entries"]) == 3
      assert last[key]["next_after"] == nil
      ids = Enum.map(first[key]["entries"] ++ last[key]["entries"], & &1["id"])
      assert ids == Enum.sort(ids)
      assert length(Enum.uniq(ids)) == 28
      refute Enum.any?(ids, &String.starts_with?(&1, "foreign"))
    end

    encoded = Jason.encode!(first)

    for forbidden <- ~w(api_token token_digest metadata private_marker),
        do: refute(String.contains?(encoded, forbidden))

    assert first["issued_identity"] == nil
  end

  test "empty organizations and malformed or unknown cursor keys", c do
    assert {:ok, data} = OrganizationDetail.load(c.scope, c.org.organization_id)

    for key <- ~w(members invitations services),
        do: assert(data[key] == %{"entries" => [], "next_after" => nil})

    for params <- [
          %{"members_after" => []},
          %{"members_after" => "../bad"},
          %{"organization_id" => c.other.organization_id},
          %{"unknown" => "value"}
        ] do
      assert {:error, _} = OrganizationDetail.load(c.scope, c.org.organization_id, params)
    end

    assert {:error, _} = OrganizationDetail.load(c.scope, "missing")
  end

  test "service identity issuance preserves duplicate credentials and cannot inject authority",
       c do
    input = %{"display_name" => "Flight API", "service_identity_id" => "svc-issued"}
    assert {:ok, first} = ServiceIdentityIssuance.issue(c.scope, c.org.organization_id, input)
    assert {:ok, authenticated} = Auth.authenticate_api_token(first["api_token"])
    assert authenticated.organization_id == c.org.organization_id
    assert authenticated.service_identity.capabilities == [:organization_admin]

    assert {:invalid, %{"service_identity_id" => _}} =
             ServiceIdentityIssuance.issue(c.scope, c.org.organization_id, input)

    assert {:invalid, %{"service_identity_id" => _}} =
             ServiceIdentityIssuance.issue(c.scope, c.other.organization_id, input)

    assert {:ok, original} = Auth.authenticate_api_token(first["api_token"])
    assert original.organization_id == c.org.organization_id

    for invalid <- [
          Map.put(input, "organization_id", c.other.organization_id),
          Map.put(input, "capabilities", ["mission_admin"]),
          %{input | "service_identity_id" => "../bad"},
          %{input | "display_name" => ""}
        ] do
      assert {:invalid, _} =
               ServiceIdentityIssuance.issue(c.scope, c.org.organization_id, invalid)
    end

    assert {:ok, data} = OrganizationDetail.load(c.scope, c.org.organization_id)
    assert length(data["services"]["entries"]) == 1
    refute String.contains?(Jason.encode!(data), first["api_token"])
  end

  test "fresh privilege removal and inactive users deny reads and both effects", c do
    service = %{"display_name" => "Denied", "service_identity_id" => "denied"}

    invitation = %{
      "email" => "denied@example.test",
      "display_name" => "Denied",
      "membership_role" => "member",
      "grant_platform_admin" => false
    }

    for scope <- [
          nil,
          %Scope{},
          %{c.scope | actor_kind: :service},
          %{c.scope | admin_mode?: false}
        ] do
      assert {:error, _} = OrganizationDetail.load(scope, c.org.organization_id)
      assert {:error, _} = ServiceIdentityIssuance.issue(scope, c.org.organization_id, service)

      assert {:error, _} =
               OrganizationInvitations.create(scope, c.org.organization_id, invitation)
    end

    Repo.get!(UserRow, c.user.user_id)
    |> Ecto.Changeset.change(lifecycle_state: "disabled")
    |> Repo.update!()

    assert {:error, _} = OrganizationDetail.load(c.scope, c.org.organization_id)
    assert {:error, _} = ServiceIdentityIssuance.issue(c.scope, c.org.organization_id, service)

    assert {:error, _} =
             OrganizationInvitations.create(c.scope, c.org.organization_id, invitation)

    Repo.get!(UserRow, c.user.user_id)
    |> Ecto.Changeset.change(lifecycle_state: "active", capabilities: [])
    |> Repo.update!()

    assert {:error, _} = OrganizationDetail.load(c.scope, c.org.organization_id)
    assert {:error, _} = ServiceIdentityIssuance.issue(c.scope, c.org.organization_id, service)

    assert {:error, _} =
             OrganizationInvitations.create(c.scope, c.org.organization_id, invitation)

    assert Auth.list_service_identities(c.org.organization_id) == []
  end

  defp user!(id, capabilities, state \\ :active) do
    user =
      User.new(%{
        user_id: id,
        email: "#{id}@example.test",
        display_name: id,
        capabilities: capabilities,
        lifecycle_state: state
      })

    Repo.insert!(UserRow.changeset(user))
    user
  end

  defp organization!(slug) do
    {:ok, org} =
      Organizations.persist_organization(
        Organization.new(%{organization_id: "org-#{slug}", slug: slug, display_name: slug})
      )

    org
  end

  defp member!(org, id, user_state \\ :active) do
    user = user!("user-#{id}", [], user_state)

    row =
      OrganizationMembership.new(%{
        organization_membership_id: id,
        organization_id: org.organization_id,
        user_id: user.user_id,
        role: :member,
        lifecycle_state: :active
      })

    Repo.insert!(OrganizationMembershipRow.changeset(row))
  end

  defp invitation!(
         org,
         id,
         user,
         status \\ :pending,
         expires \\ DateTime.add(DateTime.utc_now(), 3600)
       ) do
    row =
      OrganizationInvitation.new(%{
        organization_invitation_id: id,
        organization_id: org.organization_id,
        email: "#{id}@example.test",
        membership_role: :member,
        grant_platform_admin: false,
        status: status,
        token_digest: "digest-#{id}",
        token_hint: "hint",
        expires_at: expires,
        invited_by_user_id: user.user_id,
        metadata: %{"private_marker" => "not returned"}
      })

    Repo.insert!(OrganizationInvitationRow.changeset(row))
  end

  defp service!(org, id) do
    {:ok, _} =
      Auth.issue_service_identity(
        ServiceIdentity.new(%{
          service_identity_id: id,
          organization_id: org.organization_id,
          display_name: id,
          capabilities: [:organization_admin],
          metadata: %{"private_marker" => "not returned"}
        })
      )
  end
end
