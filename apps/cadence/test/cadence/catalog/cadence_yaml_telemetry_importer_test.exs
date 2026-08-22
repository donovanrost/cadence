defmodule Cadence.Catalog.CadenceYamlTelemetryImporterTest do
  use Cadence.ConfigCase, async: false

  alias Cadence.Jobs.Runner, as: JobRunner

  alias Cadence.Catalog.Artifact
  alias Cadence.MissionModels
  alias Cadence.Runtime.MissionModelPlanDecoder

  @organization_id "org-alpha"
  @mission_id "mission-alpha"

  test "imports Cadence YAML into one native Mission Model and runnable target plans" do
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
             Cadence.Catalog.persist_artifact(@organization_id, artifact)

    assert {:ok, queued_run} =
             Cadence.Catalog.start_import_run(
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
    assert {:ok, completed_job} = JobRunner.run_job(queued_job.job_id)
    assert completed_job.status == :completed

    assert {:ok, completed_run} =
             Cadence.Catalog.fetch_import_run(
               @organization_id,
               @mission_id,
               queued_run.import_run_id
             )

    assert completed_run.status == :completed, inspect(completed_run.failure_reason, pretty: true)
    assert completed_run.imported_definition_count == 4

    refute Map.has_key?(completed_run.result_document, "telemetry_snapshot")
    refute Map.has_key?(completed_run.result_document, "command_snapshot")

    revision_id = completed_run.result_document["mission_model"]["revision_id"]

    assert {:ok, revision} =
             MissionModels.fetch_revision(@organization_id, @mission_id, revision_id)

    assert revision.status == :candidate

    assert {:ok, plans} =
             MissionModels.fetch_runtime_plans(@organization_id, @mission_id, revision_id)

    assert Enum.all?(plans, fn {_target, plan} -> plan.status == :ready end)
    assert "MM_CALIBRATOR_RUNTIME_UNSUPPORTED" in Enum.map(plans.telemetry.diagnostics, & &1.code)
    assert :ok = MissionModelPlanDecoder.validate(plans)

    assert {:ok, [packet_definition]} =
             MissionModelPlanDecoder.telemetry_packet_definitions(plans)

    assert packet_definition.packet_name == "THERM"

    assert Enum.map(packet_definition.fields, &{&1.name, &1.data_type}) == [
             {"temperature_c", :float},
             {"heater_enabled", :bool}
           ]

    assert Enum.map(plans.command.plan["runtime_definitions"], & &1["name"]) == [
             "NOOP",
             "SAFE_MODE",
             "SET_MODE"
           ]
  end

  test "imports the demo spacecraft YAML fixture as a combined native Mission Model" do
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
             Cadence.Catalog.persist_artifact(@organization_id, artifact)

    assert {:ok, queued_run} =
             Cadence.Catalog.start_import_run(
               @organization_id,
               @mission_id,
               persisted_artifact.artifact_id,
               "cadence_yaml"
             )

    assert {:ok, queued_job} =
             Cadence.Jobs.fetch_job_for_run(:catalog_import_run, queued_run.import_run_id)

    assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_job.job_id == queued_job.job_id
    assert {:ok, completed_job} = JobRunner.run_job(queued_job.job_id)
    assert completed_job.status == :completed

    assert {:ok, completed_run} =
             Cadence.Catalog.fetch_import_run(
               @organization_id,
               @mission_id,
               queued_run.import_run_id
             )

    assert completed_run.status == :completed, inspect(completed_run.failure_reason, pretty: true)
    assert completed_run.imported_definition_count > 10
    revision_id = completed_run.result_document["mission_model"]["revision_id"]

    assert {:ok, plans} =
             MissionModels.fetch_runtime_plans(@organization_id, @mission_id, revision_id)

    assert length(plans.command.plan["runtime_definitions"]) > 10
    assert length(plans.telemetry.plan["packet_definitions"]) > 5
  end

  test "lowers binary telemetry fields into the native telemetry plan" do
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
             Cadence.Catalog.persist_artifact(@organization_id, artifact)

    assert {:ok, queued_run} =
             Cadence.Catalog.start_import_run(
               @organization_id,
               @mission_id,
               persisted_artifact.artifact_id,
               "cadence_yaml"
             )

    assert {:ok, queued_job} =
             Cadence.Jobs.fetch_job_for_run(:catalog_import_run, queued_run.import_run_id)

    assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_job.job_id == queued_job.job_id
    assert {:ok, completed_job} = JobRunner.run_job(queued_job.job_id)
    assert completed_job.status == :completed

    assert {:ok, completed_run} =
             Cadence.Catalog.fetch_import_run(
               @organization_id,
               @mission_id,
               queued_run.import_run_id
             )

    assert completed_run.status == :completed

    revision_id = completed_run.result_document["mission_model"]["revision_id"]

    assert {:ok, plans} =
             MissionModels.fetch_runtime_plans(@organization_id, @mission_id, revision_id)

    assert {:ok, [packet_definition]} =
             MissionModelPlanDecoder.telemetry_packet_definitions(plans)

    assert packet_definition.packet_name == "SCIENCE_FRAME"

    assert [%{name: "data_block", data_type: :binary, size_bits: 32_672}] =
             packet_definition.fields
  end
end
