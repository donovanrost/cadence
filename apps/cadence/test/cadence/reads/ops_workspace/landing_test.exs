defmodule Cadence.Reads.OpsWorkspace.LandingTest do
  use Cadence.DataCase, async: false

  alias Cadence.Auth.Scope
  alias Cadence.Reads.OpsWorkspace.Landing

  @org "org-workspace-landing"
  @mission "mission-workspace-landing"

  setup do
    persist_mission_scope(@org, @mission)

    scope = %Scope{
      actor_kind: :user,
      user: %{user_id: "workspace-operator"},
      organization_id: @org,
      organization_membership: %{lifecycle_state: :active}
    }

    %{scope: scope}
  end

  test "foreign, missing, bound-other-mission and inactive scopes do not expose navigation", c do
    persist_mission_scope("org-foreign-landing", "mission-foreign-landing")
    assert {:error, :unavailable} = Landing.load(c.scope, "mission-foreign-landing")
    assert {:error, :unavailable} = Landing.load(c.scope, "missing")
    assert {:error, :unavailable} = Landing.load(%{c.scope | mission_id: "other"}, @mission)

    assert {:error, :unavailable} =
             Landing.load(
               %{c.scope | organization_membership: %{lifecycle_state: :inactive}},
               @mission
             )

    assert {:error, :unavailable} = Landing.load(%Scope{}, @mission)
  end
end
