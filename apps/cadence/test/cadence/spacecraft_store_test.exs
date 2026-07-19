defmodule Cadence.SpacecraftStoreTest do
  use Cadence.DataCase, async: false

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

    assert {:ok, persisted_spacecraft} =
             Cadence.SpacecraftStore.persist_spacecraft("org-spacecraft", spacecraft)

    assert persisted_spacecraft.organization_id == "org-spacecraft"
    assert persisted_spacecraft.mission_id == "mission-spacecraft"
    assert persisted_spacecraft.display_name == "SC-001"
    assert persisted_spacecraft.scid == 42

    assert {:ok, fetched_spacecraft} =
             Cadence.SpacecraftStore.fetch_spacecraft(
               "org-spacecraft",
               "mission-spacecraft",
               "spacecraft-001"
             )

    assert fetched_spacecraft == persisted_spacecraft

    assert [listed_spacecraft] =
             Cadence.SpacecraftStore.list_spacecraft("org-spacecraft", "mission-spacecraft")

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
        applications: %{"telemetry_decom" => %{}}
      })

    assert {:ok, persisted_type} =
             Cadence.SpacecraftTypeStore.persist_spacecraft_type("org-spacecraft", type)

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

    assert {:ok, persisted} =
             Cadence.SpacecraftStore.persist_spacecraft("org-spacecraft", spacecraft)

    assert persisted.spacecraft_type_id == persisted_type.spacecraft_type_id
    assert persisted.spacecraft_type_version == 1

    assert {:ok, fetched} =
             Cadence.SpacecraftStore.fetch_spacecraft(
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

    assert {:ok, _persisted_spacecraft} =
             Cadence.SpacecraftStore.persist_spacecraft("org-spacecraft", spacecraft)

    updated =
      Spacecraft.new(%{
        spacecraft
        | display_name: "SC-001 Prime",
          scid: 8
      })

    assert {:ok, persisted_update} =
             Cadence.SpacecraftStore.update_spacecraft("org-spacecraft", updated)

    assert persisted_update.display_name == "SC-001 Prime"
    assert persisted_update.scid == 8

    assert {:ok, fetched_spacecraft} =
             Cadence.SpacecraftStore.fetch_spacecraft(
               "org-spacecraft",
               "mission-spacecraft",
               "spacecraft-001"
             )

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

    assert {:ok, persisted_spacecraft} =
             Cadence.SpacecraftStore.persist_spacecraft("org-spacecraft", spacecraft)

    assert {:ok, endpoint} =
             Cadence.SpacecraftStore.ensure_managed_source_endpoint(
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

    assert {:ok, persisted_update} =
             Cadence.SpacecraftStore.update_spacecraft("org-spacecraft", updated)

    assert {:ok, updated_endpoint} =
             Cadence.SpacecraftStore.ensure_managed_source_endpoint(
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

  describe "list_spacecraft_page/3" do
    setup context do
      {organization_id, mission_id} = fleet_scope(context)

      persist_mission_scope(organization_id, mission_id)

      fleet_spacecraft!(organization_id, mission_id, "alpha",
        display_name: "Alpha-1",
        scid: 101,
        type: {"type-a", 2}
      )

      fleet_spacecraft!(organization_id, mission_id, "bravo",
        display_name: "Bravo-2",
        scid: 202,
        type: {"type-a", 1}
      )

      fleet_spacecraft!(organization_id, mission_id, "charlie",
        display_name: "Charlie 100%",
        scid: nil,
        type: {"type-b", 1}
      )

      fleet_spacecraft!(organization_id, mission_id, "delta",
        display_name: "Delta-4",
        scid: 404,
        type: nil
      )

      %{fleet_organization_id: organization_id, fleet_mission_id: mission_id}
    end

    test "search matches display name and scid as text", context do
      assert names(context, search: "alpha") == ["Alpha-1"]
      assert names(context, search: "20") == ["Bravo-2"]
    end

    test "search escapes ILIKE metacharacters", context do
      assert names(context, search: "100%") == ["Charlie 100%"]
      assert names(context, search: "%") == ["Charlie 100%"]
    end

    test "sorts by scid descending with stable tiebreak", context do
      assert names(context, sort: {:scid, :desc}) == [
               "Delta-4",
               "Bravo-2",
               "Alpha-1",
               "Charlie 100%"
             ]
    end

    test "paginates and reports the filtered total", context do
      page =
        Cadence.SpacecraftStore.list_spacecraft_page(
          context.fleet_organization_id,
          context.fleet_mission_id,
          page: 2,
          page_size: 3
        )

      assert page.total_count == 4
      assert page.page == 2
      assert page.page_size == 3
      assert [%Spacecraft{display_name: "Delta-4"}] = page.items
    end

    test "filters missing profile and missing scid", context do
      assert names(context, filter: :missing_profile) == ["Delta-4"]
      assert names(context, filter: :missing_scid) == ["Charlie 100%"]
    end

    test "filters by profile and by stale versions", context do
      assert names(context, filter: {:profile, "type-a"}) == ["Alpha-1", "Bravo-2"]
      assert names(context, filter: {:stale_versions, %{"type-a" => 2}}) == ["Bravo-2"]
      assert names(context, filter: {:stale_versions, %{}}) == []
    end
  end

  describe "fleet_summary/2" do
    test "computes totals and per-profile-version counts", context do
      {organization_id, mission_id} = fleet_scope(context)

      persist_mission_scope(organization_id, mission_id)

      fleet_spacecraft!(organization_id, mission_id, "alpha",
        display_name: "Alpha-1",
        scid: 101,
        type: {"type-a", 2}
      )

      fleet_spacecraft!(organization_id, mission_id, "bravo",
        display_name: "Bravo-2",
        scid: 202,
        type: {"type-a", 1}
      )

      fleet_spacecraft!(organization_id, mission_id, "charlie",
        display_name: "Charlie-3",
        scid: nil,
        type: {"type-a", 2}
      )

      fleet_spacecraft!(organization_id, mission_id, "delta",
        display_name: "Delta-4",
        scid: 404,
        type: nil
      )

      summary = Cadence.SpacecraftStore.fleet_summary(organization_id, mission_id)

      assert summary.total == 4
      assert summary.missing_scid == 1
      assert summary.missing_profile == 1

      assert Enum.sort_by(summary.profile_version_counts, & &1.spacecraft_type_version) == [
               %{spacecraft_type_id: "type-a", spacecraft_type_version: 1, count: 1},
               %{spacecraft_type_id: "type-a", spacecraft_type_version: 2, count: 2}
             ]
    end

    test "returns zeroed summary for an empty mission", context do
      {organization_id, mission_id} = fleet_scope(context)

      persist_mission_scope(organization_id, mission_id)

      summary = Cadence.SpacecraftStore.fleet_summary(organization_id, mission_id)

      assert summary == %{
               total: 0,
               missing_scid: 0,
               missing_profile: 0,
               profile_version_counts: []
             }
    end
  end

  defp fleet_scope(context) do
    suffix = System.unique_integer([:positive])
    test_name = context.test |> Atom.to_string() |> String.replace(~r/[^a-zA-Z0-9]+/, "-")

    {"org-fleet-#{test_name}-#{suffix}", "mission-fleet-#{test_name}-#{suffix}"}
  end

  defp fleet_spacecraft!(organization_id, mission_id, id, opts) do
    {type_id, type_version} =
      case Keyword.get(opts, :type) do
        {type_id, version} -> {type_id, version}
        nil -> {nil, nil}
      end

    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "#{mission_id}-spacecraft-#{id}",
        organization_id: organization_id,
        mission_id: mission_id,
        display_name: Keyword.fetch!(opts, :display_name),
        scid: Keyword.get(opts, :scid),
        spacecraft_type_id: type_id,
        spacecraft_type_version: type_version
      })

    {:ok, persisted} = Cadence.SpacecraftStore.persist_spacecraft(organization_id, spacecraft)
    persisted
  end

  defp names(context, opts) do
    context.fleet_organization_id
    |> Cadence.SpacecraftStore.list_spacecraft_page(context.fleet_mission_id, opts)
    |> Map.fetch!(:items)
    |> Enum.map(& &1.display_name)
  end
end
