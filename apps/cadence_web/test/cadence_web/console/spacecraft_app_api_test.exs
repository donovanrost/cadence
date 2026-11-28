defmodule CadenceWeb.Console.SpacecraftAppAPITest do
  @moduledoc "L19: the apps installable on one spacecraft."
  use CadenceWeb.ConnCase, async: false

  import Ecto.Query

  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Applications.TelemetryDecom
  alias Cadence.Auth.Scope
  alias Cadence.Catalog.ConfigurationReviews
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
      base: "/api/v1/missions/#{mission.mission_id}/spacecraft/#{craft.spacecraft_id}/apps",
      missing: "/api/v1/missions/#{mission.mission_id}/spacecraft/nope/apps"
    }
  end

  defp get_conn(c, path), do: c.user |> TestFixtures.member_conn() |> get(path)

  # A request that reviewed this spacecraft's configuration, and no other.
  defp review(c) do
    {:ok, ref} =
      ConfigurationReviews.store(c.org.organization_id, c.mission.mission_id, [
        %{id: c.craft.spacecraft_id, configuration_revision_id: "r-1", configuration_token: "t"}
      ])

    %{"configuration_review" => ConfigurationReviews.metadata(ref, nil)}
  end

  test "lists the spacecraft-scope apps; an unknown one is 404", c do
    data = c |> get_conn(c.base) |> json_response(200) |> Map.fetch!("data")

    assert data["permissions"] == ["apps.install"]
    keys = Enum.map(data["apps"], & &1["key"])
    assert "telemetry_decom" in keys

    for app <- data["apps"] do
      assert %{"state" => _, "status" => _} = app
      refute Map.has_key?(app, "surfaces")
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
        metadata: review(c)
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

    # #471 (#146's rule): the requester is named while an active member; never by email.
    requested_by = fn ->
      c
      |> get_conn(c.base)
      |> json_response(200)
      |> get_in(["data", "apps"])
      |> Enum.find(&(&1["key"] == "telemetry_decom"))
      |> get_in(["status", "activation_request", "requested_by"])
    end

    assert requested_by.() == %{"name" => c.user.display_name}

    id = c.user.user_id

    Cadence.Repo.update_all(
      from(u in Cadence.Accounts.UserRow, where: u.user_id == ^id),
      set: [display_name: ""]
    )

    assert requested_by.() == nil
  end

  # An outsider can't request at all (forbidden), so the case is a requester who has since left.
  test "a requester who has left the organization isn't named, and no email is sent", c do
    c.user |> TestFixtures.member_conn() |> post(c.base <> "/telemetry_decom/install", %{})

    binding =
      BindingSet.new(%{
        organization_id: c.org.organization_id,
        mission_id: c.mission.mission_id,
        binding_set_id: TelemetryDecom.binding_set_id(c.mission.mission_id),
        version: 1
      })

    {:ok, binding} = Cadence.Governance.persist_binding_set(c.org.organization_id, binding)

    leaver = TestFixtures.persist_user!(display_name: "Former Member")
    membership = TestFixtures.grant_membership!(leaver, c.org, role: :organization_admin)

    scope = %Scope{
      actor_kind: :user,
      user: leaver,
      organization_id: c.org.organization_id,
      mission_id: c.mission.mission_id,
      organization_membership: membership,
      capabilities: MapSet.new([:organization_admin])
    }

    {:ok, _request} =
      Activations.request(scope, c.mission.mission_id, binding.binding_set_id, 1,
        metadata: review(c)
      )

    leaver_id = leaver.user_id

    Cadence.Repo.update_all(
      from(m in Cadence.Accounts.OrganizationMembershipRow, where: m.user_id == ^leaver_id),
      set: [lifecycle_state: "revoked"]
    )

    body = c |> get_conn(c.base) |> json_response(200)
    app = Enum.find(body["data"]["apps"], &(&1["key"] == "telemetry_decom"))

    assert %{"state" => "activation_pending", "activation_request" => %{"requested_by" => nil}} =
             app["status"]

    refute Jason.encode!(body) =~ leaver.email
    refute Jason.encode!(body) =~ "Former Member"
  end
end
