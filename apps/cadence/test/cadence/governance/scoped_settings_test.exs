defmodule Cadence.Governance.ScopedSettingsTest do
  use Cadence.DataCase, async: false
  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Auth.Scope
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Management.Activations
  alias Cadence.Management.Commanding.WorkspaceSettings
  alias Cadence.Platform.ScopedReadUpdates
  alias Cadence.Platform.ScopedSettings

  setup do
    org = "settings-org-#{System.unique_integer([:positive])}"
    mission = "settings-mission-#{System.unique_integer([:positive])}"
    other = mission <> "-other"
    persist_mission_scope(org, mission)
    persist_mission_scope(org, other)

    %{
      org: org,
      mission: mission,
      other: other,
      scope: member(org, "maya"),
      reviewer: member(org, "eli")
    }
  end

  test "organization defaults, mission overrides, enforcement, and reset keep separate revisions",
       c do
    save_policy(c.scope, nil, "independent", true)
    save_policy(c.scope, c.mission, "direct")
    assert ActivationPolicy.load(c.org, c.mission).source == "overridden"
    assert ActivationPolicy.load(c.org, c.other).source == "inherited"
    save_policy(c.scope, nil, "independent", false)
    enforced = ActivationPolicy.load(c.org, c.mission)
    assert enforced.source == "enforced"
    assert enforced.saved == %{"approval_requirement" => "direct"}
    assert enforced.effective == %{"approval_requirement" => "independent"}

    assert {:error, :settings_enforced_by_organization} =
             ActivationPolicy.save(c.scope, c.mission, enforced.token, %{"value" => nil})

    save_policy(c.scope, nil, "independent", true)
    restored = ActivationPolicy.load(c.org, c.mission)
    assert restored.effective == %{"approval_requirement" => "direct"}
    assert {:ok, _} = ActivationPolicy.save(c.scope, c.mission, restored.token, %{"value" => nil})
    assert ActivationPolicy.load(c.org, c.mission).source == "inherited"
  end

  test "stale writes and tokens from another mission cannot overwrite settings", c do
    before = ActivationPolicy.load(c.org, c.mission)
    save_policy(c.scope, nil, "independent", true)

    assert {:error, :settings_changed} =
             ActivationPolicy.save(c.scope, c.mission, before.token, %{
               "value" => %{"approval_requirement" => "direct"}
             })

    other = ActivationPolicy.load(c.org, c.other)

    assert {:error, :settings_changed} =
             ActivationPolicy.save(c.scope, c.mission, other.token, %{"value" => nil})
  end

  test "named settings permissions admit ordinary members and reject revoked or foreign scopes",
       c do
    assert MapSet.size(c.scope.capabilities) == 0
    save_policy(c.scope, c.mission, "direct")
    current = ActivationPolicy.load(c.org, c.mission)

    revoked = %{
      c.scope
      | organization_membership: %{c.scope.organization_membership | lifecycle_state: :revoked}
    }

    assert {:error, :forbidden} =
             ActivationPolicy.save(revoked, c.mission, current.token, %{"value" => nil})

    assert {:error, :scope_mismatch} =
             ActivationPolicy.save(%{c.scope | mission_id: c.other}, c.mission, current.token, %{
               "value" => nil
             })

    assert {:error, :mission_not_found} =
             ActivationPolicy.save(member("other-org", "other"), c.mission, current.token, %{
               "value" => nil
             })
  end

  test "sections own validation and saving Commanding does not change Governance", c do
    governance = ActivationPolicy.load(c.org, c.mission)
    commanding = WorkspaceSettings.load(c.org, c.mission)

    assert {:ok, revision} =
             WorkspaceSettings.save(c.scope, c.mission, commanding.token, %{
               "value" => %{"shelf" => "minimized"}
             })

    assert ActivationPolicy.load(c.org, c.mission) == governance
    assert WorkspaceSettings.load(c.org, c.mission).effective == %{"shelf" => "minimized"}

    assert [%{id: id, actor: "maya", version: 1}] =
             ScopedSettings.history(c.org, c.mission, "commanding.defaults")

    assert id == revision.revision_id

    assert {:error, :invalid_settings} =
             ActivationPolicy.save(c.scope, c.mission, governance.token, %{
               "value" => %{"approval_requirement" => "skip_validation"}
             })

    assert {:error, :invalid_settings} =
             ActivationPolicy.save(c.scope, c.mission, governance.token, %{
               "value" => nil,
               "organization_id" => "other-org"
             })
  end

  test "independent review accepts another ordinary member and forbids self approval", c do
    save_policy(c.scope, nil, "independent", true)
    request = request(c)

    assert {:error, :activation_self_approval_forbidden} =
             Activations.approve(c.scope, request.activation_request_id, "Reviewed")

    assert {:ok, _, _, _} =
             Activations.approve(c.reviewer, request.activation_request_id, "Reviewed")
  end

  test "relaxing settings invalidates a pending review without approving it", c do
    save_policy(c.scope, nil, "independent", true)
    request = request(c)
    save_policy(c.scope, c.mission, "direct")

    assert {:error, :activation_policy_changed} =
             Activations.approve(c.reviewer, request.activation_request_id, "Reviewed")

    assert {:ok, %{state: :approval_pending}} =
             Activations.fetch(c.scope, request.activation_request_id)

    assert request(c).state == :approved
  end

  test "a changed policy blocks an already approved handoff before recording an activation", c do
    save_policy(c.scope, nil, "independent", true)
    request = request(c)

    assert {:ok, _, _, _} =
             Activations.approve(c.reviewer, request.activation_request_id, "Reviewed")

    save_policy(c.scope, c.mission, "direct")

    assert {:error, :activation_policy_changed} =
             Cadence.Activations.record_binding_set_activation(
               c.org,
               c.mission,
               request.binding_set_id,
               request.binding_set_version,
               activation_request_id: request.activation_request_id,
               binding_set_content_sha256: request.binding_set_content_sha256
             )

    assert Cadence.Activations.list_activations(c.org, c.mission) == []
  end

  test "only committed settings publish scoped updates", c do
    :ok = ScopedReadUpdates.subscribe(:settings_changed, c.org, c.mission)
    save_policy(c.scope, c.mission, "direct")
    assert_receive {:settings_changed, org, mission}
    assert {org, mission} == {c.org, c.mission}
    current = ActivationPolicy.load(c.org, c.mission)

    assert {:error, :rolled_back} =
             ActivationPolicy.with_lock(c.org, fn ->
               assert {:ok, _} =
                        ActivationPolicy.save(c.scope, c.mission, current.token, %{"value" => nil})

               {:error, :rolled_back}
             end)

    refute_receive {:settings_changed, _, _}
    assert ActivationPolicy.load(c.org, c.mission).token == current.token
  end

  defp save_policy(scope, mission, requirement, allowed \\ true) do
    input = %{"value" => %{"approval_requirement" => requirement}}
    input = if is_nil(mission), do: Map.put(input, "allow_override", allowed), else: input
    current = ActivationPolicy.load(scope.organization_id, mission)
    assert {:ok, _} = ActivationPolicy.save(scope, mission, current.token, input)
  end

  defp request(c) do
    binding =
      BindingSet.new(%{
        organization_id: c.org,
        mission_id: c.mission,
        binding_set_id: "basis-#{System.unique_integer([:positive])}",
        version: 1
      })

    {:ok, _} = Cadence.Governance.persist_binding_set(c.org, binding)
    assert {:ok, request} = Activations.request(c.scope, c.mission, binding.binding_set_id, 1)
    request
  end

  defp member(org, id) do
    Scope.new(%{
      user: User.new(%{user_id: id, email: id <> "@example.test", display_name: id}),
      organization_id: org,
      organization_membership: OrganizationMembership.new(%{organization_id: org, user_id: id})
    })
  end
end
