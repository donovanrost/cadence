defmodule Cadence.Applications.TelemetryDecomTest do
  use Cadence.DataCase, async: true

  alias Cadence.Applications.TelemetryDecom
  alias Cadence.Applications.TelemetryDecomFixtures

  @organization_id "org-decom-data"
  @mission_id "mission-decom-data"

  describe "list_revision_apid_rows/3" do
    test "groups Mission Model packet definitions by APID and sorts by APID" do
      {_spacecraft, revision, _endpoint} = setup_imported_mission!()

      assert {:ok, %{rows: rows, points_by_id: points_by_id}} =
               TelemetryDecom.list_revision_apid_rows(
                 @organization_id,
                 @mission_id,
                 revision.catalog_revision_id
               )

      assert [%{apid: 42, packets: packets, def_count: 1} | _] = rows
      assert [%Cadence.Telemetry.PacketDefinition{packet_name: "HEALTH", apid: 42}] = packets
      assert is_map(points_by_id)
    end

    test "returns an error tuple when the revision does not exist" do
      persist_mission_scope(@organization_id, @mission_id)

      assert {:error, _} =
               TelemetryDecom.list_revision_apid_rows(
                 @organization_id,
                 @mission_id,
                 "nonexistent-revision-id"
               )
    end
  end

  defp setup_imported_mission! do
    TelemetryDecomFixtures.setup_imported_mission!(@organization_id, @mission_id)
  end
end
