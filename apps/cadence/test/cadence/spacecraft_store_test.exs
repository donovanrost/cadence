defmodule Cadence.SpacecraftStoreTest do
  use Cadence.DataCase, async: true

  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft

  test "persists and lists mission-owned spacecraft" do
    persist_mission_scope("org-spacecraft", "mission-spacecraft")

    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "spacecraft-001",
        organization_id: "org-spacecraft",
        mission_id: "mission-spacecraft",
        display_name: "SC-001"
      })

    assert {:ok, persisted_spacecraft} = Cadence.persist_spacecraft("org-spacecraft", spacecraft)

    assert persisted_spacecraft.organization_id == "org-spacecraft"
    assert persisted_spacecraft.mission_id == "mission-spacecraft"
    assert persisted_spacecraft.display_name == "SC-001"

    assert {:ok, fetched_spacecraft} =
             Cadence.fetch_spacecraft("org-spacecraft", "mission-spacecraft", "spacecraft-001")

    assert fetched_spacecraft == persisted_spacecraft

    assert [listed_spacecraft] = Cadence.list_spacecraft("org-spacecraft", "mission-spacecraft")
    assert listed_spacecraft == persisted_spacecraft
  end

  test "rejects source endpoints that reference a spacecraft missing from the mission" do
    persist_mission_scope("org-spacecraft", "mission-spacecraft")

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "source-endpoint-001",
        organization_id: "org-spacecraft",
        mission_id: "mission-spacecraft",
        spacecraft_id: "spacecraft-missing",
        source_ref: "sc-001"
      })

    assert {:error, :spacecraft_not_found} =
             Cadence.persist_source_endpoint("org-spacecraft", source_endpoint)
  end
end
