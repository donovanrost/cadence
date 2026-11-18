defmodule Cadence.Management.ApprovalSettingAccessTest do
  @moduledoc """
  #233 (user ruling 11-18): the console's Settings read says what THIS viewer may change in the
  approval setting, and it never disagrees with `ActivationPolicy.save/4`: every value offered
  saves, every value withheld is refused, and `can_inherit` says whether clearing the mission's
  own value saves. While the organization doesn't allow an override, nobody changes a mission's.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Auth.Scope
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Management.ApprovalSettingAccess

  @values ["direct", "independent"]

  setup do
    org = "approval-access-org-#{System.unique_integer([:positive])}"
    mission = "approval-access-mission-#{System.unique_integer([:positive])}"
    persist_mission_scope(org, mission)

    %{
      org: org,
      mission: mission,
      operator: person(org, "operator"),
      mission_admin: person(org, "mission-admin", [:mission_admin], mission),
      org_admin: person(org, "org-admin", [:organization_admin]),
      platform_admin: person(org, "platform-admin", [:platform_admin])
    }
  end

  test "each role's flags, on a mission that inherits 'independent'", c do
    assert flags(c, c.org_admin) == %{allowed_values: @values, can_inherit: true}
    assert flags(c, c.platform_admin) == %{allowed_values: @values, can_inherit: true}
    # Already the strictest: nothing to tighten; inheriting 'independent' isn't looser.
    assert flags(c, c.mission_admin) == %{allowed_values: [], can_inherit: true}
    assert flags(c, c.operator) == %{allowed_values: [], can_inherit: false}
  end

  test "a mission an organization admin loosened: the mission admin may tighten it", c do
    {:ok, _} = save(c.org_admin, c.mission, %{"approval_requirement" => "direct"})

    assert flags(c, c.mission_admin) == %{allowed_values: ["independent"], can_inherit: true}
    assert flags(c, c.operator) == %{allowed_values: [], can_inherit: false}
  end

  test "an organization that defaults to 'direct': a mission admin can't hand a stricter mission back",
       c do
    {:ok, _} = save_org(c, "direct", true)
    {:ok, _} = save(c.org_admin, c.mission, %{"approval_requirement" => "independent"})

    assert flags(c, c.mission_admin) == %{allowed_values: [], can_inherit: false}
  end

  test "the organization's own fields: only an organization admin", c do
    for {scope, allowed?} <- [{c.org_admin, true}, {c.mission_admin, false}, {c.operator, false}] do
      snapshot = ActivationPolicy.settings_snapshot(c.org, nil)

      assert ApprovalSettingAccess.flags(scope, nil, "approval_requirement", snapshot) ==
               %{allowed_values: if(allowed?, do: @values, else: [])}

      assert ApprovalSettingAccess.flags(scope, nil, "allow_override", snapshot) ==
               %{allowed_values: if(allowed?, do: [true, false], else: [])}
    end
  end

  test "while the organization doesn't allow an override, nobody changes a mission's value", c do
    {:ok, _} = save_org(c, "independent", false)

    for scope <- [c.org_admin, c.mission_admin, c.operator] do
      assert flags(c, scope) == %{allowed_values: [], can_inherit: false}

      assert {:error, :settings_enforced_by_organization} =
               save(scope, c.mission, %{"approval_requirement" => "independent"})
    end
  end

  test "the flags never disagree with the save, for every role, state and value", c do
    states = [
      fn -> :ok end,
      fn -> {:ok, _} = save(c.org_admin, c.mission, %{"approval_requirement" => "direct"}) end,
      fn ->
        {:ok, _} = save_org(c, "direct", true)
        {:ok, _} = save(c.org_admin, c.mission, %{"approval_requirement" => "independent"})
      end
    ]

    for state <- states, scope <- [c.org_admin, c.mission_admin, c.operator] do
      at = fn ->
        reset!(c)
        state.()
      end

      at.()
      %{allowed_values: allowed, can_inherit: inherit?} = flags(c, scope)
      current = requirement(c)

      for value <- @values do
        at.()
        saved? = match?({:ok, _}, save(scope, c.mission, %{"approval_requirement" => value}))
        who = "#{scope.user.user_id}: #{value} from #{current}"

        # Offered: it saves. Withheld: refused, except a no-change save the console doesn't offer.
        if value in allowed, do: assert(saved?, who)
        if value not in allowed and value != current, do: refute(saved?, who)
      end

      at.()
      assert inherit? == match?({:ok, _}, save(scope, c.mission, nil)), "#{scope.user.user_id}"
    end
  end

  defp flags(c, scope) do
    snapshot = ActivationPolicy.load(c.org, c.mission)
    ApprovalSettingAccess.flags(scope, c.mission, "approval_requirement", snapshot)
  end

  defp requirement(c),
    do: ActivationPolicy.load(c.org, c.mission).effective["approval_requirement"]

  defp save(scope, mission, value) do
    policy = ActivationPolicy.load(scope.organization_id, mission)
    ActivationPolicy.save(scope, mission, policy.token, %{"value" => value})
  end

  defp save_org(c, requirement, allow_override) do
    policy = ActivationPolicy.load(c.org, nil)

    ActivationPolicy.save(c.org_admin, nil, policy.token, %{
      "value" => %{"approval_requirement" => requirement},
      "allow_override" => allow_override
    })
  end

  defp reset!(c) do
    Repo.query!(
      "DELETE FROM scoped_settings_revisions WHERE organization_id = $1",
      [c.org]
    )
  end

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
