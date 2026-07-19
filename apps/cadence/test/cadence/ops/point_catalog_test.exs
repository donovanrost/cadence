defmodule Cadence.Ops.PointCatalogTest do
  # async: false — registers the fake catalog importer via Application.put_env.
  use Cadence.ConfigCase, async: false

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}
  alias Cadence.Catalog
  alias Cadence.Catalog.Telemetry.Snapshot
  alias Cadence.Telemetry.PacketDefinition

  setup do
    previous_importers = Application.get_env(:cadence, :catalog_importers, [])

    Application.put_env(:cadence, :catalog_importers, [
      Cadence.TestSupport.FakeTelemetryCatalogImporter
    ])

    on_exit(fn ->
      Application.put_env(:cadence, :catalog_importers, previous_importers)
    end)

    organization_id = "org-point-catalog"
    mission_id = "mission-point-catalog"

    persist_mission_scope(organization_id, mission_id)

    %{organization_id: organization_id, mission_id: mission_id}
  end

  test "returns no points without an active binding set", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    assert [] = Cadence.list_ops_telemetry_points(organization_id, mission_id)
  end

  test "lists points from the active binding set enriched from catalog snapshots", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    activate_binding_set_fixture(organization_id, mission_id)
    persist_snapshot_fixture(organization_id, mission_id)

    assert [bus_voltage, counter] =
             Cadence.list_ops_telemetry_points(organization_id, mission_id)

    assert %{
             point_id: "HK.bus_voltage",
             packet_name: "HK",
             field_name: "bus_voltage",
             unit: "V",
             stale_timeout_ms: nil,
             description: nil
           } = bus_voltage

    assert %{
             point_id: "HK.counter",
             packet_name: "HK",
             field_name: "counter",
             stale_timeout_ms: 5_000,
             description: "Cycle counter"
           } = counter
  end

  defp activate_binding_set_fixture(organization_id, mission_id) do
    packet_definition =
      PacketDefinition.new(%{
        mission_id: mission_id,
        packet_definition_id: "hk-packet",
        packet_name: "HK",
        apid: 42,
        fields: [
          %{
            field_id: "field-counter",
            name: "counter",
            offset_bits: 0,
            size_bits: 16,
            data_type: :uint
          },
          %{
            name: "bus_voltage",
            offset_bits: 16,
            size_bits: 16,
            data_type: :uint,
            engineering_unit: "V"
          }
        ]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: mission_id,
        binding_set_id: mission_id <> "-binding-set",
        version: 1,
        rules: [
          BindingRule.new(%{
            handler_key: :definition_bound_telemetry,
            packet_kind: :space_packet,
            apid: 42,
            handler_configuration: packet_definition
          })
        ]
      })

    {:ok, persisted} = Cadence.persist_binding_set(organization_id, binding_set)

    {:ok, _activation} =
      Cadence.activate_binding_set(
        organization_id,
        mission_id,
        persisted.binding_set_id,
        persisted.version,
        []
      )

    persisted
  end

  defp persist_snapshot_fixture(organization_id, mission_id) do
    artifact =
      Catalog.Artifact.new(%{
        artifact_id: "artifact-point-catalog",
        organization_id: organization_id,
        mission_id: mission_id,
        catalog_family: :telemetry,
        artifact_name: "point-catalog.json",
        format_key: "fake_tm_json",
        media_type: "application/json",
        source_artifact: %{"packets" => [%{"name" => "HK"}]},
        uploaded_by: %{"service_identity_id" => "svc-test"}
      })

    {:ok, _artifact} = Cadence.Catalog.persist_artifact(organization_id, artifact)

    {:ok, import_run} =
      Cadence.Catalog.start_import_run(
        organization_id,
        mission_id,
        "artifact-point-catalog",
        "fake_tm_json",
        requested_by: %{"service_identity_id" => "svc-test"}
      )

    snapshot =
      Snapshot.new(%{
        snapshot_id: "telemetry_snapshot:point-catalog",
        organization_id: organization_id,
        mission_id: mission_id,
        artifact_id: "artifact-point-catalog",
        import_run_id: import_run.import_run_id,
        importer_key: "fake_tm_json",
        snapshot_name: "Point Catalog Fixture",
        points: [
          %{
            point_id: "field-counter",
            snapshot_id: "telemetry_snapshot:point-catalog",
            name: "counter",
            type_ref: "type-uint",
            stale_timeout_ms: 5_000,
            description: "Cycle counter"
          }
        ]
      })

    {:ok, persisted} = Catalog.persist_telemetry_snapshot(organization_id, snapshot)
    persisted
  end
end
