defmodule Cadence.SpacecraftFacadeTest do
  use Cadence.DataCase, async: true

  alias Cadence.Missions.Mission
  alias Cadence.Organizations.Organization
  alias Cadence.Spacecraft

  defp seed_org_and_mission do
    org =
      Organization.new(%{
        display_name: "Acme",
        slug: "acme-#{System.unique_integer([:positive])}"
      })

    {:ok, org} = Cadence.persist_organization(org)

    mission =
      Mission.new(%{
        organization_id: org.organization_id,
        slug: "m-#{System.unique_integer([:positive])}",
        display_name: "Mission One"
      })

    {:ok, mission} = Cadence.persist_mission(mission)
    {org, mission}
  end

  test "persist_spacecraft/2 + fetch_spacecraft/3 round-trip" do
    {org, mission} = seed_org_and_mission()

    spacecraft =
      Spacecraft.new(%{
        mission_id: mission.mission_id,
        display_name: "Sat-1"
      })

    assert {:ok, persisted} = Cadence.persist_spacecraft(org.organization_id, spacecraft)
    assert persisted.organization_id == org.organization_id
    assert persisted.mission_id == mission.mission_id
    assert persisted.display_name == "Sat-1"

    assert {:ok, fetched} =
             Cadence.fetch_spacecraft(
               org.organization_id,
               mission.mission_id,
               persisted.spacecraft_id
             )

    assert fetched.spacecraft_id == persisted.spacecraft_id
    assert fetched.display_name == "Sat-1"
  end

  test "list_spacecraft/2 returns only spacecraft for the given org + mission" do
    {org_a, mission_a} = seed_org_and_mission()
    {_org_b, mission_b} = seed_org_and_mission()

    {:ok, _} =
      Cadence.persist_spacecraft(
        org_a.organization_id,
        Spacecraft.new(%{mission_id: mission_a.mission_id, display_name: "A1"})
      )

    {:ok, _} =
      Cadence.persist_spacecraft(
        org_a.organization_id,
        Spacecraft.new(%{mission_id: mission_a.mission_id, display_name: "A2"})
      )

    {:ok, _} =
      Cadence.persist_spacecraft(
        mission_b.organization_id,
        Spacecraft.new(%{mission_id: mission_b.mission_id, display_name: "B1"})
      )

    names =
      Cadence.list_spacecraft(org_a.organization_id, mission_a.mission_id)
      |> Enum.map(& &1.display_name)

    assert Enum.sort(names) == ["A1", "A2"]
  end

  test "fetch_spacecraft/3 returns error for the wrong organization" do
    {org_a, mission_a} = seed_org_and_mission()
    {org_b, _mission_b} = seed_org_and_mission()

    {:ok, persisted} =
      Cadence.persist_spacecraft(
        org_a.organization_id,
        Spacecraft.new(%{mission_id: mission_a.mission_id, display_name: "Cross-org test"})
      )

    assert {:error, :spacecraft_not_found} =
             Cadence.fetch_spacecraft(
               org_b.organization_id,
               mission_a.mission_id,
               persisted.spacecraft_id
             )
  end
end
