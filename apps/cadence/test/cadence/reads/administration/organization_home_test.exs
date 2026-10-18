defmodule Cadence.Reads.Administration.OrganizationHomeTest do
  use Cadence.DataCase, async: false
  import Ecto.Query
  alias Cadence.Accounts.{OrganizationMembership, OrganizationMembershipRow, User, UserRow}
  alias Cadence.Auth.Scope
  alias Cadence.{Missions, Organizations, Repo, Spacecraft, SpacecraftStore}
  alias Cadence.Missions.{Mission, MissionRow}
  alias Cadence.Organizations.Organization
  alias Cadence.Reads.Administration.OrganizationHome

  @org "org-home-owner"
  @probe Path.expand(
           "../../../../../../frontend/apps/host/src/administration/features/organization-home/producer-consumer-probe.mjs",
           __DIR__
         )

  setup do
    assert {:ok, _} =
             Organizations.persist_organization(
               Organization.new(%{
                 organization_id: @org,
                 slug: "home-owner",
                 display_name: "Home Owner",
                 metadata: %{"private" => "not a home field"}
               })
             )

    scope = %Scope{
      actor_kind: :user,
      user: %{user_id: "home-operator"},
      organization_id: @org,
      organization_membership: %{lifecycle_state: :active}
    }

    %{scope: scope}
  end

  test "counted organization totals and the actual three newest missions reach the public component",
       c do
    for i <- 1..24, do: mission("mission-old-#{i}", "a-old-#{i}", ~U[2026-09-01 00:00:00.000000Z])
    latest = mission("mission-new", "z-new", ~U[2026-09-09 00:00:00.000000Z])
    mission("mission-tie-b", "b-tie", ~U[2026-09-08 00:00:00.000000Z])
    mission("mission-tie-a", "c-tie", ~U[2026-09-08 00:00:00.000000Z])
    for i <- 1..4, do: spacecraft(latest, "home-craft-#{i}")
    membership("active-one", :active)
    membership("active-disabled-user", :active, :disabled)
    membership("revoked", :revoked)
    foreign = persist_mission_scope("foreign-home-org", "foreign-home-mission")
    spacecraft(foreign.mission, "foreign-home-craft")

    assert {:ok, doc} = OrganizationHome.load(c.scope)
    assert doc["organization"]["id"] == @org
    assert doc["counts"] == %{"missions" => 27, "spacecraft" => 4, "active_memberships" => 2}

    assert Enum.map(doc["recent_missions"], & &1["id"]) == [
             "mission-new",
             "mission-tie-a",
             "mission-tie-b"
           ]

    refute Map.has_key?(doc["organization"], "metadata")
    refute Enum.any?(doc["recent_missions"], &Map.has_key?(&1, "status"))
    {output, status} = System.cmd("node", [@probe, Jason.encode!(doc)], stderr_to_stdout: true)
    assert status == 0, output
    assert output =~ "ORGANIZATION_HOME_CONSUMER_OK"
  end

  test "empty organizations retain explicit zero totals", c do
    assert {:ok, doc} = OrganizationHome.load(c.scope)
    assert doc["counts"] == %{"missions" => 0, "spacecraft" => 0, "active_memberships" => 0}
    assert doc["recent_missions"] == []
  end

  test "anonymous, service and revoked membership reads are rejected", c do
    for scope <- [
          nil,
          %Scope{},
          %{c.scope | user: nil},
          %{c.scope | actor_kind: :service},
          %{c.scope | organization_membership: %{lifecycle_state: :revoked}}
        ] do
      assert {:error, _} = OrganizationHome.load(scope)
    end
  end

  defp mission(id, slug, created_at) do
    assert {:ok, mission} =
             Missions.persist_mission(
               Mission.new(%{
                 mission_id: id,
                 organization_id: @org,
                 slug: slug,
                 display_name: slug,
                 metadata: %{"private" => "not a home field"}
               })
             )

    from(row in MissionRow, where: row.mission_id == ^id)
    |> Repo.update_all(set: [inserted_at: created_at])

    mission
  end

  defp spacecraft(mission, id) do
    assert {:ok, _} =
             SpacecraftStore.persist_spacecraft(
               mission.organization_id,
               Spacecraft.new(%{
                 mission_id: mission.mission_id,
                 spacecraft_id: id,
                 display_name: id
               })
             )
  end

  defp membership(id, state, user_state \\ :active) do
    user =
      User.new(%{
        user_id: id,
        display_name: id,
        email: id <> "@example.test",
        lifecycle_state: user_state
      })

    assert {:ok, _} = Repo.insert(UserRow.changeset(user))

    member =
      OrganizationMembership.new(%{user_id: id, organization_id: @org, lifecycle_state: state})

    assert {:ok, _} = Repo.insert(OrganizationMembershipRow.changeset(member))
  end
end
