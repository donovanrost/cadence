defmodule Cadence.Reads.OrganizationAuditNamesTest do
  @moduledoc """
  #470 (#462, #146 rule C1 and its exception for the organization's own Audit; OK'd by
  ca-security, ux and lead). One test per ca-security condition:

  1. Only the organization's own Audit names former members; every other read keeps C1.
  2. Only people with a membership row in that organization, in any state. A platform admin, or
     anyone never a member, is `{user, nil, nil}`.
  3. Display name only, never the email; without one, "a member".
  4. The exception is recorded in setup.md's C1.
  5. An erased person reads unnamed (when offboarding can erase, #220).

  Plus the P1: a platform admin's act in a customer's Audit carries neither their id, nor their
  name, nor their email.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.{
    MembershipAdministration,
    OrganizationMembership,
    OrganizationMembershipRow,
    User,
    UserRow
  }

  alias Cadence.Administration.PlatformEvents
  alias Cadence.Control.ActorRef
  alias Cadence.Platform.ScopedSettings.RevisionRow
  alias Cadence.Reads.OrganizationAudit

  @org "org-470"
  @other "org-470-other"

  setup do
    persist_mission_scope(@org, "mission-470")
    persist_mission_scope(@other, "mission-470-other")

    person!("mira-470", "Mira K.", @org, :organization_admin)
    person!("rae-470", "Rae Removed", @org, :member)
    person!("nameless-470", "Placeholder", @org, :member)
    {1, _} = Repo.update_all(where(UserRow, user_id: "nameless-470"), set: [display_name: ""])
    person!("elsewhere-470", "Ezra Elsewhere", @other, :member)
    person!("pat-470", "Pat Platform", @other, :member, [:platform_admin])

    # Mira removes Rae, who is then a former member; the nameless member's role changes.
    {:ok, _} = MembershipAdministration.remove_member(@org, "rae-470", "mira-470")

    {:ok, _} =
      MembershipAdministration.change_role(@org, "nameless-470", :organization_admin, "mira-470")

    :ok
  end

  describe "condition 1: only the organization's own Audit names former members" do
    test "the Audit names the removed member by display name" do
      assert "Removed Rae Removed from the organization" in actions(audit())
    end

    test "every other read keeps C1: the former member is unnamed and has no id" do
      assert ActorRef.resolve(@org, "rae-470") == %{kind: "user", id: nil, name: nil}
    end

    test "only Reads.OrganizationAudit calls MemberNames.ever_members/2" do
      callers =
        for file <- Path.wildcard(Path.join(lib(), "**/*.ex")),
            File.read!(file) =~ "ever_members(",
            not String.ends_with?(file, "accounts/member_names.ex"),
            do: Path.relative_to(file, lib())

      assert callers == ["cadence/reads/organization_audit.ex"]
    end
  end

  describe "condition 2: only people with a membership row in this organization" do
    test "a former member's own past acts keep their name" do
      record_settings!("rae-470")
      assert %{id: "rae-470", name: "Rae Removed"} = settings_actor(audit())
    end

    test "a platform admin from elsewhere, or anyone never a member, is {user, nil, nil}" do
      record_settings!("elsewhere-470")
      assert settings_actor(audit()) == %{kind: "user", id: nil, name: nil}
    end
  end

  describe "condition 3: display name only, never the email" do
    test "a member without a display name reads 'a member', and no email appears anywhere" do
      events = audit()
      assert Enum.any?(actions(events), &(&1 =~ "Changed a member's role"))
      body = Jason.encode!(events)
      refute body =~ "@example.test"
    end
  end

  describe "condition 4: the exception is recorded where the rule lives" do
    test "setup.md's C1 records it with ca-security's conditions and the OK" do
      c1 = File.read!(Path.join(root(), "docs/apogee/api/setup.md"))
      assert c1 =~ "#470"
      assert c1 =~ "own Audit"
    end
  end

  describe "condition 5: an erased person reads unnamed" do
    test "once the user row is gone, their past act is {user, nil, nil}" do
      record_settings!("mira-470")
      Repo.delete_all(where(UserRow, user_id: "mira-470"))
      assert settings_actor(audit()) == %{kind: "user", id: nil, name: nil}
    end
  end

  describe "the P1: a platform admin's act in the customer's own Audit" do
    test "carries neither their id, nor their name, nor their email" do
      :ok =
        PlatformEvents.record("pat-470", "organization_created", %{
          organization_id: @org,
          target: {"organization", @org, "Org 470"}
        })

      events = audit()
      assert %{actor: actor} = Enum.find(events, &(&1.kind == "platform"))
      assert actor == %{kind: "user", id: nil, name: nil}

      body = Jason.encode!(events)
      refute body =~ "pat-470"
      refute body =~ "Pat Platform"
      refute body =~ "pat-470@example.test"
    end
  end

  test "an actor with a stored name but no id is unnamed; Cadence's own keeps its name" do
    events =
      OrganizationAudit.named(
        [
          %{actor: %{kind: "user", id: nil, name: "stored@example.test"}},
          %{actor: %{kind: "service", id: nil, name: "Stored service"}},
          %{actor: %{kind: "system", id: "cadence:seed", name: "Cadence"}},
          %{actor: nil}
        ],
        @org
      )

    assert Enum.map(events, & &1.actor) == [
             %{kind: "user", id: nil, name: nil},
             %{kind: "service", id: nil, name: nil},
             %{kind: "system", id: "cadence:seed", name: "Cadence"},
             nil
           ]
  end

  defp audit, do: OrganizationAudit.list(@org, %{offset: 0, limit: 200}).events
  defp actions(events), do: Enum.map(events, & &1.action)

  defp settings_actor(events) do
    %{actor: actor} = Enum.find(events, &(&1.target && &1.target.kind == "settings"))
    actor
  end

  defp record_settings!(actor_id) do
    Repo.insert!(
      RevisionRow.changeset(%{
        revision_id: "settings-470-#{actor_id}",
        organization_id: @org,
        scope_key: "organization",
        section_id: "commanding.defaults",
        version: 1,
        document: %{"value" => %{}, "allow_override" => true},
        actor_id: actor_id,
        actor_name: "stored-#{actor_id}@example.test"
      })
    )
  end

  defp person!(id, name, organization_id, role, capabilities \\ []) do
    Repo.insert!(
      UserRow.changeset(
        User.new(%{
          user_id: id,
          email: "#{id}@example.test",
          display_name: name,
          capabilities: capabilities
        })
      )
    )

    Repo.insert!(
      OrganizationMembershipRow.changeset(
        OrganizationMembership.new(%{user_id: id, organization_id: organization_id, role: role})
      )
    )
  end

  defp lib, do: Path.expand("../../../lib", __DIR__)
  defp root, do: Path.expand("../../../../..", __DIR__)
end
