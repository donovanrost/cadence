defmodule CadenceWeb.Console.SpacecraftAppAPITest do
  @moduledoc "L19: the apps installable on one spacecraft."
  use CadenceWeb.ConnCase, async: false

  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Applications.TelemetryDecom
  alias Cadence.Auth.Scope
  alias Cadence.Management.Activations
  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)
    craft = TestFixtures.persist_spacecraft!(mission, display_name: "EARENDIL-004")

    %{
      user: user,
      org: org,
      membership: membership,
      mission: mission,
      craft: craft,
      base:
        "/api/console/v1/missions/#{mission.mission_id}/spacecraft/#{craft.spacecraft_id}/apps",
      missing: "/api/console/v1/missions/#{mission.mission_id}/spacecraft/nope/apps"
    }
  end

  defp get_conn(c, path), do: c.user |> TestFixtures.member_conn() |> get(path)

  test "lists the spacecraft-scope apps with only spacecraft surfaces; an unknown one is 404",
       c do
    data = c |> get_conn(c.base) |> json_response(200) |> Map.fetch!("data")

    assert data["permissions"] == ["apps.install"]
    keys = Enum.map(data["apps"], & &1["key"])
    assert "telemetry_decom" in keys

    for app <- data["apps"], surface <- app["surfaces"] do
      assert surface["scope"] == "spacecraft"
    end

    for app <- data["apps"] do
      assert %{"state" => _, "status" => _} = app
    end

    assert c |> get_conn(c.missing) |> json_response(404) |> get_in(["error", "code"]) ==
             "spacecraft_not_found"
  end

  test "activation_pending counts only a request that touches this spacecraft", c do
    other = TestFixtures.persist_spacecraft!(c.mission, display_name: "EARENDIL-005")
    other_base = String.replace(c.base, c.craft.spacecraft_id, other.spacecraft_id)

    for base <- [c.base, other_base] do
      c.user
      |> TestFixtures.member_conn()
      |> post(base <> "/telemetry_decom/install", %{})
      |> json_response(200)
    end

    binding =
      BindingSet.new(%{
        organization_id: c.org.organization_id,
        mission_id: c.mission.mission_id,
        binding_set_id: TelemetryDecom.binding_set_id(c.mission.mission_id),
        version: 1
      })

    {:ok, binding} = Cadence.Governance.persist_binding_set(c.org.organization_id, binding)

    scope = %Scope{
      actor_kind: :user,
      user: c.user,
      organization_id: c.org.organization_id,
      mission_id: c.mission.mission_id,
      organization_membership: c.membership,
      capabilities: MapSet.new([:organization_admin])
    }

    {:ok, _request} =
      Activations.request(scope, c.mission.mission_id, binding.binding_set_id, 1,
        metadata: %{"triggering_spacecraft_id" => c.craft.spacecraft_id}
      )

    state = fn base ->
      c
      |> get_conn(base)
      |> json_response(200)
      |> get_in(["data", "apps"])
      |> Enum.find(&(&1["key"] == "telemetry_decom"))
      |> get_in(["status", "state"])
    end

    assert state.(c.base) == "activation_pending"
    refute state.(other_base) == "activation_pending"
  end
end
