defmodule Cadence.Auth.ManageMissionPolicyTest do
  @moduledoc """
  #1158: `:manage_mission` checks the mission against the organization itself, for every
  principal. A mission that doesn't exist or belongs to another organization is refused (a
  platform admin included), and a service pinned to one mission administers only that one, even
  when it holds `organization_admin`.
  """
  use Cadence.DataCase, async: true

  alias Cadence.Auth.{Policy, Scope}

  @org "org-1158"
  @mission "mission-1158"
  @other_mission "mission-1158-b"

  setup do
    persist_mission_scope(@org, @mission)
    persist_mission_scope(@org, @other_mission)
    persist_mission_scope("org-elsewhere-1158", "mission-elsewhere-1158")
    :ok
  end

  defp authorize(scope, mission, org \\ @org),
    do: Policy.authorize(scope, :manage_mission, %{organization_id: org, mission_id: mission})

  describe "a person" do
    test "an organization admin administers a mission of the organization" do
      assert authorize(person(@org, [:organization_admin]), @mission) == :ok
      assert authorize(person(@org, [:organization_admin]), @other_mission) == :ok
    end

    test "but not a mission of another organization, or one that doesn't exist" do
      admin = person(@org, [:organization_admin])
      assert authorize(admin, "mission-elsewhere-1158") == {:error, :scope_mismatch}
      assert authorize(admin, "no-such-mission") == {:error, :scope_mismatch}
      assert authorize(admin, nil) == {:error, :scope_mismatch}
    end

    test "a member, or another organization's admin, is refused as before" do
      assert authorize(person(@org, []), @mission) == {:error, :forbidden}

      assert authorize(person("org-elsewhere-1158", [:organization_admin]), @mission) ==
               {:error, :scope_mismatch}
    end

    test "a platform admin administers any organization's mission, if it is that organization's" do
      platform = person("org-elsewhere-1158", [:platform_admin])
      assert authorize(platform, @mission) == :ok

      # It no longer skips the mission check: the mission must be the organization's.
      assert authorize(platform, "mission-elsewhere-1158") == {:error, :scope_mismatch}
      assert authorize(platform, "no-such-mission") == {:error, :scope_mismatch}
    end
  end

  describe "a service" do
    test "an organization_admin service pinned to a mission administers only that mission" do
      svc = service([:organization_admin], @mission)
      assert authorize(svc, @mission) == :ok
      assert authorize(svc, @other_mission) == {:error, :forbidden}
    end

    test "a service pinned to a mission, holding mission_admin, administers its own mission" do
      svc = service([:mission_admin], @mission)
      assert authorize(svc, @mission) == :ok
      assert authorize(svc, @other_mission) == {:error, :forbidden}
    end

    test "an organization-wide service with organization_admin administers its organization's missions" do
      svc = service([:organization_admin], nil)
      assert authorize(svc, @mission) == :ok
      assert authorize(svc, @other_mission) == :ok
      assert authorize(svc, "mission-elsewhere-1158") == {:error, :scope_mismatch}
    end

    test "a service with no administering capability is refused" do
      assert authorize(service([], @mission), @mission) == {:error, :forbidden}
    end
  end

  defp service(capabilities, mission_id) do
    %Scope{
      actor_kind: :service,
      organization_id: @org,
      mission_id: mission_id,
      service_identity: %{
        service_identity_id: "svc-1158",
        organization_id: @org,
        mission_id: mission_id,
        lifecycle_state: :active
      },
      capabilities: MapSet.new(capabilities)
    }
  end

  defp person(organization_id, capabilities) do
    %Scope{
      actor_kind: :user,
      user: %{user_id: "user-1158"},
      organization_id: organization_id,
      capabilities: MapSet.new(capabilities)
    }
  end
end
