defmodule Cadence.Reads.OpsWorkspace.LandingTest do
  use Cadence.DataCase, async: false

  alias Cadence.Applications.{HostContext, SurfaceQueryRequest}
  alias Cadence.Auth.Scope
  alias Cadence.Reads.ApplicationSurfaces.OpsConsole
  alias Cadence.Reads.OpsWorkspace.Landing

  @org "org-workspace-landing"
  @mission "mission-workspace-landing"
  @probe Path.expand(
           "../../../../../../frontend/apps/host/src/ops-workspace/features/landing/producer-consumer-probe.mjs",
           __DIR__
         )

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

  test "authorized producer and legacy surface share the versioned model consumed by the real Vue feature",
       c do
    for capabilities <- [MapSet.new(), MapSet.new([:organization_admin])] do
      scope = %{c.scope | capabilities: capabilities}
      assert {:ok, model} = Landing.load(scope, @mission)
      assert model["context"] == %{"organization_id" => @org, "mission_id" => @mission}
      assert model["can_administer"] == MapSet.member?(capabilities, :organization_admin)
      assert model["version"] == 1
      refute Map.has_key?(model, "componentCount")

      request = %SurfaceQueryRequest{
        application_key: "ops_console",
        application_version: 1,
        surface_id: "workspace",
        surface_version: 1,
        query_id: "cadence.ops.workspace",
        query_version: 1,
        params: %{}
      }

      assert {:ok, response} =
               OpsConsole.load(
                 scope,
                 %HostContext{placement: :mission, mission_id: @mission},
                 request
               )

      assert response["data"]["presentation"] == %{
               "component" => "OpsConsoleLanding",
               "props" => %{"model" => model}
             }

      {output, status} =
        System.cmd("node", [@probe, Jason.encode!(model)], stderr_to_stdout: true)

      assert status == 0, output
      assert output =~ "WORKSPACE_LANDING_CONSUMER_OK"
    end
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
