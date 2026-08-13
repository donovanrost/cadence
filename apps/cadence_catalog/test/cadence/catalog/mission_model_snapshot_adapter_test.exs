defmodule Cadence.Catalog.MissionModelSnapshotAdapterTest do
  use ExUnit.Case, async: true

  alias Cadence.Catalog.Bundle
  alias Cadence.Catalog.MissionModel.Adapters.Snapshots
  alias Cadence.Catalog.MissionModel.Compiler
  alias Cadence.Catalog.Telemetry.Snapshot

  test "adapts existing telemetry snapshots into a resolvable imported layer" do
    snapshot =
      Snapshot.new(%{
        snapshot_id: "snapshot-alpha",
        organization_id: "org-alpha",
        mission_id: "mission-alpha",
        artifact_id: "artifact-alpha",
        import_run_id: "import-alpha",
        importer_key: "cadence_yaml",
        snapshot_name: "Alpha",
        types: [
          %{
            type_id: "type-temp",
            snapshot_id: "snapshot-alpha",
            name: "Temperature",
            base_type: :integer,
            encoding: %{encoding_type: :integer, size_bits: 16, integer_encoding: :unsigned}
          }
        ],
        points: [
          %{
            point_id: "point-temp",
            snapshot_id: "snapshot-alpha",
            name: "temperature",
            type_ref: "type-temp"
          }
        ],
        packets: [
          %{
            packet_id: "packet-hk",
            snapshot_id: "snapshot-alpha",
            name: "HK",
            apid: 42,
            entries: [%{packet_entry_id: "entry-temp", point_ref: "point-temp", bit_offset: 0}]
          }
        ]
      })

    layer = Snapshots.to_layer(Bundle.new(%{telemetry_snapshot: snapshot}))

    assert layer.layer_kind == :imported
    assert Enum.any?(layer.declarations, &(&1.kind == :container))
    assert Enum.any?(layer.declarations, &(&1.kind == :parameter))
    assert {:ok, result} = Compiler.compile([layer])
    assert result.revision.diagnostics == []
    assert result.plans.telemetry.status == :ready
    assert result.plans.telemetry.target_contract_version == "2"
    assert [packet_definition] = result.plans.telemetry.plan["packet_definitions"]
    assert packet_definition["packet_definition_id"] == "packet-hk"
    assert packet_definition["fields"] |> hd() |> Map.fetch!("parameter_id")
  end
end
