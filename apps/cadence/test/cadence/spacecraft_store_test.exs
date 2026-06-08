defmodule Cadence.SpacecraftStoreTest do
  use Cadence.DataCase, async: true

  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft
  alias Cadence.SpacecraftType

  test "persists and lists mission-owned spacecraft" do
    persist_mission_scope("org-spacecraft", "mission-spacecraft")

    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "spacecraft-001",
        organization_id: "org-spacecraft",
        mission_id: "mission-spacecraft",
        display_name: "SC-001",
        scid: 42
      })

    assert {:ok, persisted_spacecraft} = Cadence.persist_spacecraft("org-spacecraft", spacecraft)

    assert persisted_spacecraft.organization_id == "org-spacecraft"
    assert persisted_spacecraft.mission_id == "mission-spacecraft"
    assert persisted_spacecraft.display_name == "SC-001"
    assert persisted_spacecraft.scid == 42

    assert {:ok, fetched_spacecraft} =
             Cadence.fetch_spacecraft("org-spacecraft", "mission-spacecraft", "spacecraft-001")

    assert fetched_spacecraft == persisted_spacecraft

    assert [listed_spacecraft] = Cadence.list_spacecraft("org-spacecraft", "mission-spacecraft")
    assert listed_spacecraft == persisted_spacecraft
  end

  test "binds a spacecraft to a spacecraft profile version" do
    persist_mission_scope("org-spacecraft", "mission-spacecraft")

    type =
      SpacecraftType.new(%{
        mission_id: "mission-spacecraft",
        display_name: "Sentinel-X",
        downlink_protocol: :tm,
        uplink_protocol: :tc,
        packet_protocol: :space_packet,
        frame_parameters: %{
          "frame_size" => 1024,
          "secondary_header_length" => 0,
          "ocf_length" => 0
        },
        applications: %{telemetry_decom: %{}}
      })

    assert {:ok, persisted_type} = Cadence.persist_spacecraft_type("org-spacecraft", type)

    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "spacecraft-typed-001",
        organization_id: "org-spacecraft",
        mission_id: "mission-spacecraft",
        display_name: "Typed SC",
        scid: 42,
        spacecraft_type_id: persisted_type.spacecraft_type_id,
        spacecraft_type_version: persisted_type.version
      })

    assert {:ok, persisted} = Cadence.persist_spacecraft("org-spacecraft", spacecraft)
    assert persisted.spacecraft_type_id == persisted_type.spacecraft_type_id
    assert persisted.spacecraft_type_version == 1

    assert {:ok, fetched} =
             Cadence.fetch_spacecraft(
               "org-spacecraft",
               "mission-spacecraft",
               "spacecraft-typed-001"
             )

    assert fetched.spacecraft_type_id == persisted_type.spacecraft_type_id
    assert fetched.spacecraft_type_version == 1
  end

  test "updates spacecraft identity fields" do
    persist_mission_scope("org-spacecraft", "mission-spacecraft")

    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "spacecraft-001",
        organization_id: "org-spacecraft",
        mission_id: "mission-spacecraft",
        display_name: "SC-001",
        scid: 7
      })

    assert {:ok, _persisted_spacecraft} = Cadence.persist_spacecraft("org-spacecraft", spacecraft)

    updated =
      Spacecraft.new(%{
        spacecraft
        | display_name: "SC-001 Prime",
          scid: 8
      })

    assert {:ok, persisted_update} = Cadence.update_spacecraft("org-spacecraft", updated)
    assert persisted_update.display_name == "SC-001 Prime"
    assert persisted_update.scid == 8

    assert {:ok, fetched_spacecraft} =
             Cadence.fetch_spacecraft("org-spacecraft", "mission-spacecraft", "spacecraft-001")

    assert fetched_spacecraft.display_name == "SC-001 Prime"
    assert fetched_spacecraft.scid == 8
  end

  test "managed source endpoint is updated when spacecraft identity changes" do
    persist_mission_scope("org-spacecraft", "mission-spacecraft")

    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "spacecraft-001",
        organization_id: "org-spacecraft",
        mission_id: "mission-spacecraft",
        display_name: "SC-001",
        scid: 7
      })

    assert {:ok, persisted_spacecraft} = Cadence.persist_spacecraft("org-spacecraft", spacecraft)

    assert {:ok, endpoint} =
             Cadence.ensure_managed_spacecraft_source_endpoint(
               "org-spacecraft",
               persisted_spacecraft
             )

    assert endpoint.scid == 7

    updated =
      Spacecraft.new(%{
        persisted_spacecraft
        | display_name: "SC-001 Prime",
          scid: 8
      })

    assert {:ok, persisted_update} = Cadence.update_spacecraft("org-spacecraft", updated)

    assert {:ok, updated_endpoint} =
             Cadence.ensure_managed_spacecraft_source_endpoint(
               "org-spacecraft",
               persisted_update
             )

    assert updated_endpoint.source_endpoint_id == endpoint.source_endpoint_id
    assert updated_endpoint.display_name == "SC-001 Prime"
    assert updated_endpoint.scid == 8
    assert updated_endpoint.metadata["managed_by"] == "spacecraft"
    refute Map.has_key?(updated_endpoint.metadata, "value")
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
