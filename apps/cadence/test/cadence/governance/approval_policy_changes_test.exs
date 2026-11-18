defmodule Cadence.Governance.ApprovalPolicyChangesTest do
  @moduledoc """
  Who may change a mission's approval setting (board #233; the user's rule, DECISIONS #111): only an
  organization admin may LOOSEN it ('independent' to 'direct') or change the organization's setting
  at all (its default and whether missions may override); a mission admin may TIGHTEN their own
  mission's setting; operators can't change it. Every change records who, when, and the setting
  before and after; a refused change records nothing.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Auth.Scope
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Platform.ScopedSettings

  setup do
    org = "approval-change-org-#{System.unique_integer([:positive])}"
    mission = "approval-change-mission-#{System.unique_integer([:positive])}"
    persist_mission_scope(org, mission)

    %{
      org: org,
      mission: mission,
      operator: person(org, "operator"),
      mission_admin: person(org, "mission-admin", [:mission_admin], mission),
      org_admin: person(org, "org-admin", [:organization_admin])
    }
  end

  test "an operator can't change a mission's approval setting, in either direction", c do
    # Loosening (the default is 'independent').
    assert {:error, :approval_policy_change_requires_organization_admin} =
             set(c.operator, c.mission, "direct")

    assert unchanged?(c)

    # Tightening, from a 'direct' an organization admin set.
    assert {:ok, _} = set(c.org_admin, c.mission, "direct")
    versions = versions(c)

    assert {:error, :approval_policy_change_requires_mission_admin} =
             set(c.operator, c.mission, "independent")

    assert versions(c) == versions
    assert requirement(c) == "direct"
  end

  test "a mission admin may tighten their mission's setting, but not loosen it", c do
    assert {:error, :approval_policy_change_requires_organization_admin} =
             set(c.mission_admin, c.mission, "direct")

    assert unchanged?(c)

    assert {:ok, _} = set(c.org_admin, c.mission, "direct")
    assert {:ok, _} = set(c.mission_admin, c.mission, "independent")
    assert requirement(c) == "independent"

    assert [%{actor: "mission-admin", audit: audit} | _] = history(c, c.mission)

    assert %{
             "scope" => "mission",
             "before" => %{"effective" => %{"approval_requirement" => "direct"}},
             "after" => %{"effective" => %{"approval_requirement" => "independent"}}
           } = audit
  end

  test "pinning a mission's own 'direct' needs an organization admin, even while the organization's default is direct",
       c do
    # Pinning 'direct' while it's inherited is a loosening in advance: the organization's later
    # tightening would never reach this mission (api-ops' review, lead 11-18).
    assert {:ok, _} = set_organization(c.org_admin, "direct", true)
    assert requirement(c) == "direct"

    assert {:error, :approval_policy_change_requires_organization_admin} =
             set(c.mission_admin, c.mission, "direct")

    assert history(c, c.mission) == []

    assert {:ok, _} = set(c.org_admin, c.mission, "direct")

    # The mirror, pinning 'independent' while inheriting it, is a tightening: allowed.
    assert {:ok, _} = set_organization(c.org_admin, "independent", true)
    other = "approval-change-other-#{System.unique_integer([:positive])}"
    persist_mission_scope(c.org, other)
    other_admin = person(c.org, "other-admin", [:mission_admin], other)
    assert {:ok, _} = set(other_admin, other, "independent")
  end

  test "an organization admin may loosen a mission's setting, and the change is audited", c do
    assert {:ok, _} = set(c.org_admin, c.mission, "direct")
    assert requirement(c) == "direct"

    assert [%{actor: "org-admin", saved_at: saved_at, audit: audit} | _] = history(c, c.mission)
    assert is_binary(saved_at)

    assert %{
             "before" => %{"effective" => %{"approval_requirement" => "independent"}},
             "after" => %{
               "effective" => %{"approval_requirement" => "direct"},
               "override" => %{"approval_requirement" => "direct"}
             }
           } = audit
  end

  test "the organization's setting (default and override flag) is organization-admin only", c do
    for scope <- [c.operator, c.mission_admin] do
      assert {:error, reason} = set_organization(scope, "direct", true)

      assert reason in [
               :approval_policy_change_requires_organization_admin,
               # A mission admin's scope is bound to its mission.
               :scope_mismatch
             ]

      assert {:error, _reason} = set_organization(scope, "independent", false)
    end

    assert history(c, nil) == []

    assert {:ok, _} = set_organization(c.org_admin, "independent", false)
    assert {:ok, _} = set_organization(c.org_admin, "direct", true)

    assert [%{actor: "org-admin", audit: audit} | _] = history(c, nil)

    assert %{
             "scope" => "organization",
             "before" => %{
               "value" => %{"approval_requirement" => "independent"},
               "allow_override" => false
             },
             "after" => %{
               "value" => %{"approval_requirement" => "direct"},
               "allow_override" => true
             }
           } = audit
  end

  defp set(scope, mission, requirement) do
    current = ActivationPolicy.load(scope.organization_id, mission)

    ActivationPolicy.save(scope, mission, current.token, %{
      "value" => %{"approval_requirement" => requirement}
    })
  end

  defp set_organization(scope, requirement, allow_override) do
    current = ActivationPolicy.load(scope.organization_id, nil)

    ActivationPolicy.save(scope, nil, current.token, %{
      "value" => %{"approval_requirement" => requirement},
      "allow_override" => allow_override
    })
  end

  defp requirement(c),
    do: ActivationPolicy.load(c.org, c.mission).effective["approval_requirement"]

  defp history(c, mission),
    do: ScopedSettings.history(c.org, mission, ActivationPolicy.section_id())

  defp versions(c), do: {history(c, nil), history(c, c.mission)}

  defp unchanged?(c),
    do: history(c, c.mission) == [] and requirement(c) == "independent"

  defp person(org, id, capabilities \\ [], mission \\ nil) do
    %{
      Scope.new(%{
        user: User.new(%{user_id: id, email: id <> "@example.test", display_name: id}),
        organization_id: org,
        organization_membership: OrganizationMembership.new(%{organization_id: org, user_id: id})
      })
      | capabilities: MapSet.new(capabilities),
        mission_id: mission
    }
  end
end
