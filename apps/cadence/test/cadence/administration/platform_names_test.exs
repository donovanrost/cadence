defmodule Cadence.Administration.PlatformNamesTest do
  @moduledoc """
  #470: the platform admin area (Admin › Organizations, Service identities, Audit) may name
  anyone across organizations, because its readers are platform administrators in admin mode.
  That is enforced at the read, not only at the controller (api-ops): each read, and
  `PlatformNames` itself, refuses any other scope. People are named by display name only, never
  by email. Only `Cadence.Administration.*` may call `PlatformNames` (the guard below).
  """
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.{
    OrganizationMembership,
    OrganizationMembershipRow,
    PlatformDirectory,
    User,
    UserRow
  }

  alias Cadence.Administration.{
    ConsoleOrganizations,
    ConsoleServiceIdentities,
    PlatformAudit,
    PlatformEvents,
    PlatformNames
  }

  alias Cadence.Auth.Scope

  @org "org-470-platform"

  setup do
    persist_mission_scope(@org, "mission-470-platform")
    admin = person!("admin-470", "Ada Admin", [:platform_admin])
    member = person!("member-470", "Mira K.", [])
    nameless = person!("nameless-470p", "Placeholder", [])
    {1, _} = Repo.update_all(where(UserRow, user_id: "nameless-470p"), set: [display_name: ""])

    Repo.insert!(
      OrganizationMembershipRow.changeset(
        OrganizationMembership.new(%{
          user_id: member.user_id,
          organization_id: @org,
          role: :member
        })
      )
    )

    %{
      admin: Scope.new(%{user: admin, admin_mode?: true}),
      not_in_admin_mode: Scope.new(%{user: admin, admin_mode?: false}),
      member: Scope.new(%{user: member, organization_id: @org})
    }
  end

  describe "refused at the read for anyone but a platform admin in admin mode" do
    test "PlatformNames", c do
      for scope <- [c.member, c.not_in_admin_mode, nil] do
        assert {:error, :unavailable} = PlatformNames.display_names(scope, ["member-470"])
      end
    end

    test "the platform audit, organizations and service identities", c do
      for scope <- [c.member, c.not_in_admin_mode] do
        assert {:error, :unavailable} = PlatformAudit.list(scope, %{})
        assert {:error, :unavailable} = ConsoleOrganizations.list(scope, %{})
        assert {:error, :unavailable} = ConsoleServiceIdentities.list(scope, %{})
        assert {:error, :unavailable} = ConsoleServiceIdentities.row(scope, @org, "any")
      end
    end
  end

  describe "names by display name only, never the email" do
    test "PlatformNames: anyone, in any organization; nil without a display name", c do
      assert {:ok, names} =
               PlatformNames.display_names(c.admin, ["admin-470", "member-470", "nameless-470p"])

      assert names == %{
               "admin-470" => "Ada Admin",
               "member-470" => "Mira K.",
               "nameless-470p" => nil
             }
    end

    test "Admin › Audit names the platform admin who acted, never by email", c do
      :ok =
        PlatformEvents.record("nameless-470p", "organization_created", %{
          organization_id: @org,
          target: {"organization", @org, "Org"}
        })

      :ok =
        PlatformEvents.record("admin-470", "organization_created", %{
          organization_id: @org,
          target: {"organization", @org, "Org"}
        })

      assert {:ok, %{events: events}} = PlatformAudit.list(c.admin, %{})
      names = Map.new(events, &{&1.actor.id, &1.actor.name})
      assert names["admin-470"] == "Ada Admin"
      assert names["nameless-470p"] == nil
      refute Jason.encode!(events) =~ "@example.test"
    end

    test "a pending invitation's inviter is a display name, never the email" do
      Repo.insert!(%Cadence.Accounts.OrganizationInvitationRow{
        organization_invitation_id: "inv-470",
        organization_id: @org,
        email: "invitee@elsewhere.test",
        membership_role: "member",
        status: "pending",
        invited_by_user_id: "nameless-470p",
        token_digest: "digest-470",
        token_hint: "470",
        display_name: "Invitee",
        expires_at: DateTime.add(DateTime.utc_now(), 3600)
      })

      assert [%{inviter: nil}] = PlatformDirectory.pending_invitations(@org, 10)
    end
  end

  test "only Cadence.Administration.* calls PlatformNames or PlatformDirectory.display_names" do
    lib = Path.expand("../../../lib", __DIR__)

    callers =
      for file <- Path.wildcard(Path.join(lib, "**/*.ex")),
          File.read!(file) =~ ~r/PlatformNames\.display_names|PlatformDirectory\.display_names/,
          do: Path.relative_to(file, lib)

    assert callers != []

    for file <- callers do
      assert String.starts_with?(file, "cadence/administration/"),
             "#{file} names people for platform admins only; customer reads use Control.ActorRef"
    end
  end

  defp person!(id, name, capabilities) do
    user =
      User.new(%{
        user_id: id,
        email: "#{id}@example.test",
        display_name: name,
        capabilities: capabilities
      })

    Repo.insert!(UserRow.changeset(user))
    user
  end
end
