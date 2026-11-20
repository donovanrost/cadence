defmodule Cadence.Governance.ApprovalPolicyOverrideAuditTest do
  @moduledoc """
  #430 (domain's #403 note 2): an organization save of the approval setting records every mission
  whose effective requirement it changes, with the raw requirement before and after, computed by
  the same rule `load/2` and the mission save's judgement use (`ScopedSettings.effective_for/3`).
  Turning overrides off moves pinned missions to the default (only an 'independent' default may
  turn them off); turning them on re-applies the pins, the one that can loosen; a default change
  moves the missions that inherit it.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Auth.Scope
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Platform.ScopedSettings

  setup do
    org = "override-audit-org-#{System.unique_integer([:positive])}"
    [a, b, c] = for name <- ["a", "b", "c"], do: "#{org}-mission-#{name}"
    for mission <- [a, b, c], do: persist_mission_scope(org, mission)
    %{org: org, a: a, b: b, c: c, admin: admin(org)}
  end

  # Overrides can only be turned off with an 'independent' default (ActivationPolicy's decode), so
  # turning them off moves 'direct' pins to 'independent'.
  test "turning overrides off lists the pinned missions it moves to the default", c do
    {:ok, _} = organization(c, "independent", true)
    {:ok, _} = pin(c, c.a, "direct")

    {:ok, _} = organization(c, "independent", false)

    assert latest_missions(c) == [moved(c.a, "direct", "independent")]
    assert_agrees(c)
  end

  test "turning overrides on lists the pinned missions whose pin applies again", c do
    {:ok, _} = organization(c, "independent", true)
    {:ok, _} = pin(c, c.a, "direct")
    {:ok, _} = organization(c, "independent", false)
    assert latest_missions(c) == [moved(c.a, "direct", "independent")]

    {:ok, _} = organization(c, "independent", true)

    assert latest_missions(c) == [moved(c.a, "independent", "direct")]
    assert_agrees(c)
  end

  test "a default change lists the missions that inherit it, not the pinned ones", c do
    {:ok, _} = organization(c, "independent", true)
    {:ok, _} = pin(c, c.a, "independent")
    {:ok, _} = pin(c, c.c, "direct")

    {:ok, _} = organization(c, "direct", true)

    assert latest_missions(c) == [moved(c.b, "independent", "direct")]
    assert_agrees(c)
  end

  test "a save that moves no mission records an empty list", c do
    {:ok, _} = organization(c, "independent", true)
    {:ok, _} = pin(c, c.a, "direct")
    {:ok, _} = pin(c, c.b, "direct")
    {:ok, _} = pin(c, c.c, "direct")

    {:ok, _} = organization(c, "direct", true)

    assert latest_missions(c) == []
    assert_agrees(c)
  end

  # ca-security: the list and the effective value read agree, including a value outside the two
  # (stored before #233's decode, say). Overrides on re-apply it, and it is listed as it is.
  test "a pinned value outside the two is listed raw, and agrees with what applies", c do
    {:ok, _} = organization(c, "independent", true)
    raw_pin!(c, c.a, "mystery")
    {:ok, _} = organization(c, "independent", false)

    {:ok, _} = organization(c, "direct", true)

    assert Enum.sort_by(latest_missions(c), & &1["mission_id"]) == [
             moved(c.a, "independent", "mystery"),
             moved(c.b, "independent", "direct"),
             moved(c.c, "independent", "direct")
           ]

    assert_agrees(c)
  end

  # The one rule: for every mission, what load/2 says applies now is what the latest organization
  # save recorded as its "after" (listed) or left as it was (not listed).
  defp assert_agrees(c) do
    listed = Map.new(latest_missions(c), &{&1["mission_id"], &1["after"]})

    for mission <- [c.a, c.b, c.c] do
      applies = ActivationPolicy.load(c.org, mission).effective["approval_requirement"]

      if Map.has_key?(listed, mission),
        do: assert(applies == listed[mission]),
        else: assert(applies == previous(c, mission))
    end
  end

  # Without a listing, the mission's requirement is what applied before the latest save.
  defp previous(c, mission) do
    [latest | _] = ScopedSettings.history(c.org, nil, ActivationPolicy.section_id())
    before = latest.audit["before"]
    saved = ActivationPolicy.load(c.org, mission).saved

    ScopedSettings.effective_for(before["value"], before["allow_override"], saved)[
      "approval_requirement"
    ]
  end

  defp latest_missions(c) do
    [latest | _] = ScopedSettings.history(c.org, nil, ActivationPolicy.section_id())
    latest.audit["missions"]
  end

  defp moved(id, before, after_value),
    do: %{"mission_id" => id, "before" => before, "after" => after_value}

  defp organization(c, requirement, allow_override) do
    current = ActivationPolicy.load(c.org, nil)

    ActivationPolicy.save(c.admin, nil, current.token, %{
      "value" => %{"approval_requirement" => requirement},
      "allow_override" => allow_override
    })
  end

  defp pin(c, mission, requirement) do
    current = ActivationPolicy.load(c.org, mission)

    ActivationPolicy.save(c.admin, mission, current.token, %{
      "value" => %{"approval_requirement" => requirement}
    })
  end

  # A stored override no decode accepts today. Written through the guarded save with a check (the
  # test is the rule here), as a row from an older writer would read.
  defp raw_pin!(c, mission, value) do
    current = ActivationPolicy.load(c.org, mission)

    {:ok, _} =
      ScopedSettings.save(
        c.org,
        mission,
        ActivationPolicy.section_id(),
        %{"value" => %{"approval_requirement" => "independent"}, "allow_override" => true},
        current.token,
        %{"value" => %{"approval_requirement" => value}},
        %{id: "older-writer", name: "Older writer"},
        check: fn _current -> :ok end
      )
  end

  defp admin(org) do
    %{
      Scope.new(%{
        user: User.new(%{user_id: "admin", email: "admin@example.test", display_name: "Admin"}),
        organization_id: org,
        organization_membership:
          OrganizationMembership.new(%{organization_id: org, user_id: "admin"})
      })
      | capabilities: MapSet.new([:organization_admin])
    }
  end
end
