defmodule CadenceWeb.Console.CapabilitiesAgreementTest do
  @moduledoc """
  DECISIONS #38: every capability the console reports (session organizations,
  People members) agrees with the policy that enforces it, per role.
  """
  use CadenceWeb.ConnCase, async: true

  alias Cadence.Accounts
  alias Cadence.Administration.OrganizationPeople
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Control.Commanding.GroupAbort
  alias Cadence.Management.Commanding.ReviewAccess
  alias CadenceWeb.Console.Capabilities
  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    mission = TestFixtures.persist_mission!(org)
    admin = TestFixtures.persist_user!(display_name: "Ada Admin")
    member = TestFixtures.persist_user!(display_name: "Mira K.")

    platform =
      TestFixtures.persist_user!(display_name: "Pat Platform", capabilities: [:platform_admin])

    TestFixtures.grant_membership!(admin, org, role: :organization_admin)
    TestFixtures.grant_membership!(member, org, role: :member)

    %{org: org, mission: mission, admin: admin, member: member, platform: platform}
  end

  defp scope(user, org, admin_mode? \\ false) do
    membership =
      case Accounts.fetch_user_membership(user.user_id, org.organization_id) do
        {:ok, membership} -> membership
        _none -> nil
      end

    Scope.new(%{
      user: user,
      organization_id: org.organization_id,
      organization: org,
      organization_membership: membership,
      admin_mode?: admin_mode?
    })
  end

  # What the enforcing functions decide for this scope.
  defp enforced(scope, c) do
    commanding =
      case ReviewAccess.authorize(scope, c.mission.mission_id) do
        {:ok, _scope, _mission} -> ["command.request", "command.approve"]
        {:error, _} -> []
      end

    # Abort authorizes before it checks the reason, so a blank reason tells them apart.
    abort =
      case GroupAbort.abort(scope, c.mission.mission_id, "group_none", "") do
        {:error, :unavailable} -> []
        {:error, _authorized} -> ["command.abort"]
      end

    members =
      case OrganizationPeople.invite(scope, c.org.organization_id, %{"email" => "bad"}) do
        {:error, :forbidden} -> []
        {:error, {:invalid, _}} -> ["org.invite", "org.manage_members"]
      end

    dashboards =
      case Policy.authorize(scope, :author_dashboards, %{
             organization_id: c.org.organization_id,
             mission_id: c.mission.mission_id
           }) do
        :ok -> ["dashboard.author"]
        {:error, _} -> []
      end

    Enum.sort(commanding ++ abort ++ members ++ dashboards)
  end

  defp reported(scope) do
    scope
    |> Capabilities.organization()
    |> Enum.filter(&String.contains?(&1, "."))
    |> Enum.sort()
  end

  test "session capabilities match enforcement for every role", c do
    cases = [
      {:organization_admin, scope(c.admin, c.org)},
      {:member, scope(c.member, c.org)},
      {:platform_admin_in_admin_mode, scope(c.platform, c.org, true)},
      {:platform_admin_without_admin_mode, scope(c.platform, c.org)}
    ]

    for {role, scope} <- cases do
      assert reported(scope) == enforced(scope, c), "#{role} disagrees"
    end

    assert reported(scope(c.admin, c.org)) ==
             ~w(command.abort command.approve command.request dashboard.author org.invite org.manage_members)

    # Any mission operator may request, approve and abort commands (DECISIONS #42, #62); the
    # two-person rule (no self-approval) is enforced per request, not by the capability.
    assert reported(scope(c.member, c.org)) ==
             ~w(command.abort command.approve command.request dashboard.author)
  end

  test "People member capabilities match enforcement for each member", c do
    {:ok, people} =
      OrganizationPeople.load(scope(c.member, c.org), c.org.organization_id,
        capabilities: &Capabilities.contributed/1
      )

    for row <- people.members do
      user = Enum.find([c.admin, c.member], &(&1.user_id == row.user_id))
      # People rows carry the contributed capabilities, not dashboard authoring.
      expected = enforced(scope(user, c.org), c) -- ["dashboard.author"]
      assert Enum.sort(row.capabilities) == expected, row.display_name
    end
  end
end
