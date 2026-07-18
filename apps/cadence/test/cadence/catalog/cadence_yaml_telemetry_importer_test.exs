defmodule Cadence.Catalog.CadenceYamlTelemetryImporterTest do
  use Cadence.ConfigCase, async: false

  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Catalog.Artifact
  alias Cadence.Catalog.Command.Snapshot, as: CommandCatalogSnapshot
  alias Cadence.Catalog.Telemetry.Snapshot, as: TelemetryCatalogSnapshot
  alias Cadence.Ingress.RawEvidence

  @organization_id "org-alpha"
  @mission_id "mission-alpha"

  setup do
    previous_importers = Application.get_env(:cadence, :catalog_importers, [])

    Application.put_env(:cadence, :catalog_importers, [
      Cadence.Catalog.Importers.CadenceYamlDatabase
    ])

    on_exit(fn ->
      Application.put_env(:cadence, :catalog_importers, previous_importers)
    end)

    :ok
  end

  test "imports legacy cadence yaml into telemetry and command snapshots plus runnable telemetry runtime artifacts" do
    persist_mission_scope(@organization_id, @mission_id)

    artifact =
      Artifact.new(%{
        artifact_id: "artifact-yaml-alpha",
        organization_id: @organization_id,
        mission_id: @mission_id,
        catalog_family: :combined,
        artifact_name: "mission-alpha-dev.yaml",
        format_key: "cadence_yaml",
        media_type: "application/yaml",
        source_artifact: """
        version: "1.0.0"
        description: "Mission Alpha dev telemetry"

        packets:
          - name: THERM
            apid: 42
            items:
              - name: temperature_c
                bit_offset: 0
                bit_size: 32
                data_type: float
                endianness: big
                units: "degC"
                conversion:
                  type: polynomial
                  coefficients: [0.0, 1.0]
              - name: heater_enabled
                bit_offset: 32
                bit_size: 1
                data_type: bool

        commands:
          - name: NOOP
            opcode: 0x01
          - name: SAFE_MODE
            opcode: 0x02
          - name: SET_MODE
            opcode: 0x03
            parameters:
              - name: mode
                data_type: uint
                required: true
                bit_offset: 0
                bit_length: 8
                valid_values: [0, 1, 2, 3]
        """,
        uploaded_by: %{"service_identity_id" => "svc-bootstrap"}
      })

    assert {:ok, persisted_artifact} =
             Cadence.persist_catalog_artifact(@organization_id, artifact)

    assert {:ok, queued_run} =
             Cadence.start_catalog_import_run(
               @organization_id,
               @mission_id,
               persisted_artifact.artifact_id,
               "cadence_yaml",
               requested_by: %{"service_identity_id" => "svc-bootstrap"}
             )

    assert {:ok, queued_job} =
             Cadence.Jobs.fetch_job_for_run(:catalog_import_run, queued_run.import_run_id)

    assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_job.job_id == queued_job.job_id
    assert {:ok, completed_job} = Cadence.Jobs.run_job(queued_job.job_id)
    assert completed_job.status == :completed

    assert {:ok, completed_run} =
             Cadence.fetch_catalog_import_run(
               @organization_id,
               @mission_id,
               queued_run.import_run_id
             )

    assert completed_run.status == :completed, inspect(completed_run.failure_reason, pretty: true)
    assert completed_run.snapshot_id == "telemetry_snapshot:" <> queued_run.import_run_id
    assert completed_run.imported_definition_count == 4

    diagnostic_codes = Enum.map(completed_run.diagnostics, & &1.code)

    assert "cadence_yaml_telemetry.polynomial_preserved_not_executed" in diagnostic_codes
    refute "cadence_yaml_telemetry.commands_ignored" in diagnostic_codes

    assert {:ok, telemetry_snapshot} =
             Cadence.fetch_catalog_telemetry_snapshot(
               @organization_id,
               @mission_id,
               completed_run.snapshot_id
             )

    assert %TelemetryCatalogSnapshot{} = telemetry_snapshot
    assert telemetry_snapshot.snapshot_name == persisted_artifact.artifact_name
    assert Enum.map(telemetry_snapshot.packets, & &1.name) == ["THERM"]
    assert Enum.map(telemetry_snapshot.points, & &1.name) == ["temperature_c", "heater_enabled"]

    command_snapshot_id = completed_run.result_document["command_snapshot"]["snapshot_id"]

    assert {:ok, %CommandCatalogSnapshot{} = command_snapshot} =
             Cadence.fetch_catalog_command_snapshot(
               @organization_id,
               @mission_id,
               command_snapshot_id
             )

    assert Enum.map(command_snapshot.command_definitions, & &1.name) == [
             "NOOP",
             "SAFE_MODE",
             "SET_MODE"
           ]

    command_compilation = Cadence.compile_command_catalog_snapshot(command_snapshot)

    assert length(command_compilation.runtime_definitions) == 3

    assert Enum.map(command_compilation.runtime_definitions, & &1.name) == [
             "NOOP",
             "SAFE_MODE",
             "SET_MODE"
           ]

    assert {:ok, recompilation} =
             Cadence.recompile_catalog_telemetry_snapshot(
               @organization_id,
               @mission_id,
               completed_run.snapshot_id
             )

    assert recompilation.binding_set.binding_set_id ==
             "catalog_import:" <> completed_run.import_run_id

    assert length(recompilation.compiler_result.packet_definitions) == 1
    assert length(recompilation.compiler_result.selector_inputs) == 1
    assert recompilation.compiler_result.diagnostics == []

    assert {:ok, runtime_diff} =
             Cadence.diff_catalog_telemetry_snapshot_runtime(
               @organization_id,
               @mission_id,
               completed_run.snapshot_id
             )

    assert runtime_diff.packet_definitions.matching_count == 1
    assert runtime_diff.packet_definitions.mismatches == []
    assert runtime_diff.packet_definitions.missing_existing == []
    assert runtime_diff.packet_definitions.extra_existing == []
    assert runtime_diff.capability_instances.matching_count == 1
    assert runtime_diff.capability_instances.mismatches == []
    assert runtime_diff.binding_rules.matching_count == 1
    assert runtime_diff.binding_rules.mismatches == []

    assert {:ok, materialization} =
             Cadence.materialize_catalog_telemetry_snapshot_runtime(
               @organization_id,
               @mission_id,
               completed_run.snapshot_id
             )

    assert materialization.binding_set.binding_set_id ==
             "catalog_import:" <> completed_run.import_run_id

    assert materialization.binding_set.version == 2
    assert Enum.map(materialization.compiler_result.packet_definitions, & &1.version) == [2]

    assert {:ok, %BindingSet{} = materialized_binding_set} =
             Cadence.fetch_binding_set(
               @organization_id,
               @mission_id,
               "catalog_import:" <> completed_run.import_run_id,
               2
             )

    assert materialized_binding_set.version == 2

    assert {:ok, runtime_diff_after_materialization} =
             Cadence.diff_catalog_telemetry_snapshot_runtime(
               @organization_id,
               @mission_id,
               completed_run.snapshot_id
             )

    assert runtime_diff_after_materialization.existing_binding_set.version == 2
    assert runtime_diff_after_materialization.packet_definitions.matching_count == 1
    assert runtime_diff_after_materialization.packet_definitions.mismatches == []
    assert runtime_diff_after_materialization.capability_instances.matching_count == 1
    assert runtime_diff_after_materialization.capability_instances.mismatches == []
    assert runtime_diff_after_materialization.binding_rules.matching_count == 1
    assert runtime_diff_after_materialization.binding_rules.mismatches == []

    [packet_definition] = Cadence.list_packet_definitions(@organization_id, @mission_id)
    assert packet_definition.packet_name == "THERM"

    assert Enum.map(packet_definition.fields, &{&1.name, &1.data_type}) == [
             {"temperature_c", :float},
             {"heater_enabled", :bool}
           ]

    binding_set_document = completed_run.result_document["binding_set"]

    assert is_map(binding_set_document)

    assert {:ok, %BindingSet{} = binding_set} =
             Cadence.fetch_binding_set(
               @organization_id,
               @mission_id,
               binding_set_document["binding_set_id"],
               binding_set_document["version"]
             )

    raw_evidence =
      RawEvidence.new(%{
        mission_id: @mission_id,
        raw: build_space_packet(42, 3, <<12.5::float-32, 1::size(1), 0::size(7)>>)
      })

    assert {:ok, result} = Cadence.process_telemetry_ingress(raw_evidence, binding_set)

    assert Enum.map(result.outputs, &{&1.point_name, &1.raw_value}) == [
             {"THERM.temperature_c", 12.5},
             {"THERM.heater_enabled", true}
           ]
  end

  test "imports the legacy demo_spacecraft yaml fixture as a combined command and telemetry database" do
    persist_mission_scope(@organization_id, @mission_id)

    demo_yaml_path =
      Path.expand(
        "../../../../../legacy/cadence_legacy/priv/databases/demo_spacecraft.yaml",
        __DIR__
      )

    artifact =
      Artifact.new(%{
        artifact_id: "artifact-yaml-demo",
        organization_id: @organization_id,
        mission_id: @mission_id,
        catalog_family: :combined,
        artifact_name: "demo_spacecraft.yaml",
        format_key: "cadence_yaml",
        media_type: "application/yaml",
        source_artifact: File.read!(demo_yaml_path),
        uploaded_by: %{"service_identity_id" => "svc-bootstrap"}
      })

    assert {:ok, persisted_artifact} =
             Cadence.persist_catalog_artifact(@organization_id, artifact)

    assert {:ok, queued_run} =
             Cadence.start_catalog_import_run(
               @organization_id,
               @mission_id,
               persisted_artifact.artifact_id,
               "cadence_yaml"
             )

    assert {:ok, queued_job} =
             Cadence.Jobs.fetch_job_for_run(:catalog_import_run, queued_run.import_run_id)

    assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_job.job_id == queued_job.job_id
    assert {:ok, completed_job} = Cadence.Jobs.run_job(queued_job.job_id)
    assert completed_job.status == :completed

    assert {:ok, completed_run} =
             Cadence.fetch_catalog_import_run(
               @organization_id,
               @mission_id,
               queued_run.import_run_id
             )

    assert completed_run.status == :completed, inspect(completed_run.failure_reason, pretty: true)
    assert completed_run.snapshot_id == "telemetry_snapshot:" <> queued_run.import_run_id
    assert completed_run.imported_definition_count > 10
    assert is_map(completed_run.result_document["telemetry_snapshot"])
    assert is_map(completed_run.result_document["command_snapshot"])
    assert completed_run.result_document["command_runtime"]["runtime_definition_count"] > 10

    assert {:ok, command_snapshot} =
             Cadence.fetch_catalog_command_snapshot(
               @organization_id,
               @mission_id,
               completed_run.result_document["command_snapshot"]["snapshot_id"]
             )

    assert {:ok, telemetry_snapshot} =
             Cadence.fetch_catalog_telemetry_snapshot(
               @organization_id,
               @mission_id,
               completed_run.result_document["telemetry_snapshot"]["snapshot_id"]
             )

    assert length(command_snapshot.command_definitions) > 10
    assert length(telemetry_snapshot.packets) > 5
  end

  test "summarizes packets preserved for custom application binding when telemetry contains binary payload content" do
    persist_mission_scope(@organization_id, @mission_id)

    artifact =
      Artifact.new(%{
        artifact_id: "artifact-yaml-binary-payload",
        organization_id: @organization_id,
        mission_id: @mission_id,
        catalog_family: :combined,
        artifact_name: "science-payload.yaml",
        format_key: "cadence_yaml",
        media_type: "application/yaml",
        source_artifact: """
        packets:
          - name: SCIENCE_FRAME
            apid: 42
            items:
              - name: data_block
                bit_offset: 96
                bit_size: 32672
                data_type: binary
                description: "Raw science data (~4KB)"
        """
      })

    assert {:ok, persisted_artifact} =
             Cadence.persist_catalog_artifact(@organization_id, artifact)

    assert {:ok, queued_run} =
             Cadence.start_catalog_import_run(
               @organization_id,
               @mission_id,
               persisted_artifact.artifact_id,
               "cadence_yaml"
             )

    assert {:ok, queued_job} =
             Cadence.Jobs.fetch_job_for_run(:catalog_import_run, queued_run.import_run_id)

    assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_job.job_id == queued_job.job_id
    assert {:ok, completed_job} = Cadence.Jobs.run_job(queued_job.job_id)
    assert completed_job.status == :completed

    assert {:ok, completed_run} =
             Cadence.fetch_catalog_import_run(
               @organization_id,
               @mission_id,
               queued_run.import_run_id
             )

    assert completed_run.status == :completed

    assert "telemetry_compiler.available_for_custom_application_binding" in Enum.map(
             completed_run.diagnostics,
             & &1.code
           )

    telemetry_runtime = completed_run.result_document["telemetry_runtime"]
    assert telemetry_runtime["packet_count"] == 1
    assert telemetry_runtime["built_in_telemetry_packet_count"] == 0
    assert telemetry_runtime["custom_application_candidate_packet_count"] == 1

    assert telemetry_runtime["custom_application_candidate_packets"] == [
             %{
               "packet_id" => "telemetry_snapshot:#{queued_run.import_run_id}:packet:0",
               "packet_name" => "SCIENCE_FRAME",
               "reason" => "binary_payload_field"
             }
           ]
  end

  defp build_space_packet(apid, sequence_count, packet_data) do
    packet_length = byte_size(packet_data) - 1

    <<
      0::3,
      0::1,
      0::1,
      apid::11,
      3::2,
      sequence_count::14,
      packet_length::16,
      packet_data::binary
    >>
  end
end
