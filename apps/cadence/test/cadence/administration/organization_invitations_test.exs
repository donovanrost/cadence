defmodule Cadence.Administration.OrganizationInvitationsTest do
  use Cadence.DataCase, async: false
  alias Cadence.Accounts
  alias Cadence.Accounts.{OrganizationInvitationRow, User, UserRow}
  alias Cadence.Administration.{OrganizationInvitations, ServiceIdentityIssuance}
  alias Cadence.Auth
  alias Cadence.Auth.Scope
  alias Cadence.Organizations
  alias Cadence.Organizations.Organization
  alias Cadence.Reads.Administration.OrganizationDetail
  alias Cadence.Test.AdministrationInvitationDeliveryProbe

  setup do
    previous = Application.fetch_env(:cadence, :organization_invitation_delivery)

    Application.put_env(
      :cadence,
      :organization_invitation_delivery,
      AdministrationInvitationDeliveryProbe
    )

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:cadence, :organization_invitation_delivery, value)
        :error -> Application.delete_env(:cadence, :organization_invitation_delivery)
      end
    end)

    admin = user!("admin", [:platform_admin])
    recipient = user!("recipient", [])

    {:ok, org} =
      Organizations.persist_organization(
        Organization.new(%{
          organization_id: "org-invite",
          slug: "invited",
          display_name: "Invited organization"
        })
      )

    %{scope: Scope.new(%{user: admin, admin_mode?: true}), recipient: recipient, org: org}
  end

  test "reviewed role and platform eligibility apply on acceptance, not before", c do
    assert {:ok, read} = OrganizationInvitations.load(c.scope, c.org.organization_id)
    assert read["submitted"] == nil

    assert {:ok, receipt} =
             OrganizationInvitations.create(
               c.scope,
               c.org.organization_id,
               input(c.recipient.email)
             )

    assert receipt["delivery"] == "submitted"
    assert receipt["role"] == "organization_admin"
    assert receipt["grant_platform_admin"] == true
    assert_receive {:invitation_mail_attempt, _, _, true}
    assert Accounts.list_user_memberships(c.recipient.user_id) == []
    assert {:ok, before} = Accounts.fetch_user(c.recipient.user_id)
    refute Scope.platform_admin_eligible?(Scope.new(%{user: before}))
    assert {:ok, _} = Accounts.accept_invitation_as_user(c.recipient.user_id, receipt["id"])

    assert {:ok, member} =
             Accounts.fetch_user_membership(c.recipient.user_id, c.org.organization_id)

    assert member.role == :organization_admin
    assert {:ok, after_acceptance} = Accounts.fetch_user(c.recipient.user_id)
    assert Scope.platform_admin_eligible?(Scope.new(%{user: after_acceptance}))
    refute Scope.admin_mode?(Scope.new(%{user: after_acceptance}))
    assert {:error, _} = Accounts.accept_invitation_as_user(c.recipient.user_id, receipt["id"])
  end

  test "mail failure or exception reports the saved invitation without replaying it", c do
    for result <- [:failed, :raised] do
      Process.put(:administration_invitation_delivery_result, result)
      email = "#{result}@example.test"

      assert {:ok, receipt} =
               OrganizationInvitations.create(c.scope, c.org.organization_id, input(email))

      assert receipt["delivery"] == "unavailable"
      assert Repo.get!(OrganizationInvitationRow, receipt["id"]).status == "pending"
      assert_receive {:invitation_mail_attempt, _, _, true}
      refute_receive {:invitation_mail_attempt, _, _, _}, 10

      assert Enum.count(
               Accounts.list_pending_invitations(c.org.organization_id),
               &(&1.email == email)
             ) == 1

      for key <- ~w(invitation_token token_digest token_hint metadata),
          do: refute(Map.has_key?(receipt, key))
    end
  end

  test "a deliberate replacement revokes the prior pending invitation and malformed grants cannot persist",
       c do
    assert {:ok, first} =
             OrganizationInvitations.create(
               c.scope,
               c.org.organization_id,
               input(c.recipient.email)
             )

    assert {:ok, second} =
             OrganizationInvitations.create(
               c.scope,
               c.org.organization_id,
               input(c.recipient.email)
             )

    assert first["id"] != second["id"]
    assert Repo.get!(OrganizationInvitationRow, first["id"]).status == "revoked"
    assert Repo.get!(OrganizationInvitationRow, second["id"]).status == "pending"

    for bad <- [
          Map.put(input("new@example.test"), "organization_id", "foreign"),
          Map.put(input("new@example.test"), "grant_platform_admin", "true"),
          Map.put(input("new@example.test"), "membership_role", "owner"),
          input("invalid address")
        ] do
      assert {:invalid, _} = OrganizationInvitations.create(c.scope, c.org.organization_id, bad)
    end

    assert length(Accounts.list_pending_invitations(c.org.organization_id)) == 1
  end

  test "persisted producer documents reach the real components and their submitted effects", c do
    assert {:ok, detail} = OrganizationDetail.load(c.scope, c.org.organization_id)
    assert {:ok, invite} = OrganizationInvitations.load(c.scope, c.org.organization_id)

    probe =
      Path.expand(
        "../../../../../frontend/apps/host/src/administration/features/organization-detail/producer-consumer-probe.mjs",
        __DIR__
      )

    {output, code} =
      System.cmd(
        "node",
        [
          probe,
          Jason.encode!(%{detail: detail, invite: invite, recipient_email: c.recipient.email})
        ],
        stderr_to_stdout: true
      )

    assert code == 0, output
    [_, encoded] = Regex.run(~r/ADMIN_DETAIL_INPUT=([A-Za-z0-9+\/=]+)/, output)
    [issue, invitation] = encoded |> Base.decode64!() |> Jason.decode!()
    assert issue["event"] == "issue_service_identity"

    assert {:ok, identity} =
             ServiceIdentityIssuance.issue(c.scope, c.org.organization_id, issue["input"])

    assert {:ok, authenticated} = Auth.authenticate_api_token(identity["api_token"])
    assert authenticated.organization_id == c.org.organization_id
    assert authenticated.service_identity.capabilities == [:organization_admin]
    assert invitation["event"] == "invite"

    assert {:ok, receipt} =
             OrganizationInvitations.create(c.scope, c.org.organization_id, invitation["input"])

    assert receipt["delivery"] == "submitted"
    assert {:ok, _} = Accounts.accept_invitation_as_user(c.recipient.user_id, receipt["id"])

    assert {:ok, member} =
             Accounts.fetch_user_membership(c.recipient.user_id, c.org.organization_id)

    assert member.role == :organization_admin
    assert {:ok, accepted} = Accounts.fetch_user(c.recipient.user_id)
    assert Scope.platform_admin_eligible?(Scope.new(%{user: accepted}))
    refute Scope.admin_mode?(Scope.new(%{user: accepted}))
  end

  defp input(email),
    do: %{
      "email" => email,
      "display_name" => "Invited operator",
      "membership_role" => "organization_admin",
      "grant_platform_admin" => true
    }

  defp user!(id, capabilities) do
    user =
      User.new(%{
        user_id: id,
        email: "#{id}@example.test",
        display_name: id,
        capabilities: capabilities
      })

    Repo.insert!(UserRow.changeset(user))
    user
  end
end
