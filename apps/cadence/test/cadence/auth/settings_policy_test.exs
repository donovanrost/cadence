defmodule Cadence.Auth.SettingsPolicyTest do
  @moduledoc """
  #1159: reading settings is any active member's; writing a mission's settings is a mission
  operator's; writing an organization's settings needs an organization admin.
  """
  use Cadence.DataCase, async: true

  alias Cadence.Auth.{Policy, Scope}

  @org "org-1159"
  @mission "mission-1159"

  setup do
    persist_mission_scope(@org, @mission)
    :ok
  end

  defp authorize(scope, action, mission_id),
    do: Policy.authorize(scope, action, %{organization_id: @org, mission_id: mission_id})

  test "reading an organization's or a mission's settings is any active member's" do
    member = person(@org, [])
    assert authorize(member, :read_settings, nil) == :ok
    assert authorize(member, :read_settings, @mission) == :ok
  end

  test "writing a mission's settings is a mission operator's" do
    assert authorize(person(@org, []), :manage_settings, @mission) == :ok
    assert authorize(person(@org, [:organization_admin]), :manage_settings, @mission) == :ok
  end

  test "writing an organization's settings needs an organization admin" do
    assert authorize(person(@org, []), :manage_settings, nil) == {:error, :forbidden}
    assert authorize(person(@org, [:organization_admin]), :manage_settings, nil) == :ok

    assert authorize(person("org-other", [:organization_admin]), :manage_settings, nil) ==
             {:error, :scope_mismatch}

    assert authorize(person("org-other", [:platform_admin]), :manage_settings, nil) == :ok
  end

  test "a service identity does neither" do
    service = %Scope{
      actor_kind: :service,
      organization_id: @org,
      mission_id: @mission,
      capabilities: MapSet.new([:organization_admin])
    }

    for action <- [:read_settings, :manage_settings], mission <- [nil, @mission] do
      assert authorize(service, action, mission) == {:error, :authenticated_user_required}
    end
  end

  defp person(organization_id, capabilities) do
    %Scope{
      actor_kind: :user,
      user: %{user_id: "user-1159"},
      organization_id: organization_id,
      capabilities: MapSet.new(capabilities),
      organization_membership: %{lifecycle_state: :active}
    }
  end
end
