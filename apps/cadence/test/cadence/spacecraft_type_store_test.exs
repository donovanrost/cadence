defmodule Cadence.SpacecraftTypeStoreTest do
  use Cadence.DataCase, async: true

  alias Cadence.SpacecraftType

  describe "persist_spacecraft_type/2 and queries" do
    test "persists, fetches, lists, and tracks versions" do
      persist_mission_scope("org-st", "mission-st")

      type_v1 =
        SpacecraftType.new(%{
          mission_id: "mission-st",
          display_name: "Sentinel-X",
          downlink_protocol: :aos,
          uplink_protocol: :tc,
          packet_protocol: :space_packet,
          frame_parameters: %{"frame_size" => 1024, "insert_zone_length" => 0, "ocf_length" => 0},
          applications: %{"telemetry_decom" => %{}}
        })

      assert {:ok, persisted_v1} = Cadence.persist_spacecraft_type("org-st", type_v1)
      assert persisted_v1.organization_id == "org-st"
      assert persisted_v1.version == 1
      assert persisted_v1.downlink_protocol == :aos
      assert persisted_v1.applications == %{"telemetry_decom" => %{}}

      type_v2 =
        SpacecraftType.new(%{
          spacecraft_type_id: persisted_v1.spacecraft_type_id,
          mission_id: "mission-st",
          version: 2,
          display_name: "Sentinel-X",
          downlink_protocol: :uslp,
          uplink_protocol: :uslp,
          packet_protocol: :space_packet,
          frame_parameters: %{
            "frame_size" => 2048,
            "truncated_primary_header" => false,
            "ocf_length" => 0
          },
          applications: %{"telemetry_decom" => %{}}
        })

      assert {:ok, persisted_v2} = Cadence.persist_spacecraft_type("org-st", type_v2)
      assert persisted_v2.version == 2
      assert persisted_v2.downlink_protocol == :uslp

      assert {:ok, latest} =
               Cadence.fetch_spacecraft_type(
                 "org-st",
                 "mission-st",
                 persisted_v1.spacecraft_type_id
               )

      assert latest.version == 2

      assert {:ok, v1_fetch} =
               Cadence.fetch_spacecraft_type_version(
                 "org-st",
                 "mission-st",
                 persisted_v1.spacecraft_type_id,
                 1
               )

      assert v1_fetch.downlink_protocol == :aos

      assert [listed] = Cadence.list_spacecraft_types("org-st", "mission-st")
      assert listed.spacecraft_type_id == persisted_v1.spacecraft_type_id
      assert listed.version == 2

      versions =
        Cadence.list_spacecraft_type_versions(
          "org-st",
          "mission-st",
          persisted_v1.spacecraft_type_id
        )

      assert Enum.map(versions, & &1.version) == [2, 1]
    end

    test "keeps custom application keys as strings" do
      persist_mission_scope("org-st", "mission-st")

      type =
        SpacecraftType.new(%{
          mission_id: "mission-st",
          display_name: "Custom Apps",
          downlink_protocol: :tm,
          uplink_protocol: :tc,
          packet_protocol: :space_packet,
          frame_parameters: %{
            "frame_size" => 1024,
            "secondary_header_length" => 0,
            "ocf_length" => 0
          },
          applications: %{"custom:thermal-alerting" => %{"revision" => 1}}
        })

      assert type.applications == %{"custom:thermal-alerting" => %{"revision" => 1}}

      assert {:ok, persisted} = Cadence.persist_spacecraft_type("org-st", type)
      assert persisted.applications == %{"custom:thermal-alerting" => %{"revision" => 1}}

      assert {:ok, fetched} =
               Cadence.fetch_spacecraft_type(
                 "org-st",
                 "mission-st",
                 persisted.spacecraft_type_id
               )

      assert fetched.applications == %{"custom:thermal-alerting" => %{"revision" => 1}}
    end

    test "returns not_found for missing types" do
      persist_mission_scope("org-st", "mission-st")

      assert {:error, :spacecraft_type_not_found} =
               Cadence.fetch_spacecraft_type("org-st", "mission-st", "missing")
    end
  end
end
