defmodule Cadence.Applications.TelemetryDecomFixtures do
  @moduledoc false

  alias Cadence.Accounts.User
  alias Cadence.Auth.Scope
  alias Cadence.Catalog
  alias Cadence.Catalog.Artifact
  alias Cadence.Platform.ContentHash
  alias Cadence.Runtime.MissionModelPlanDecoder
  alias Cadence.SemanticRuntime
  alias Cadence.SemanticRuntime.{PlanDecoder, State, Update}
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft

  def setup_spacecraft!(organization_id, mission_id) do
    Cadence.DataCase.persist_mission_scope(organization_id, mission_id)
    persist_spacecraft!(organization_id, mission_id, display_name: "Nova-1")
  end

  def setup_imported_mission!(organization_id, mission_id) do
    spacecraft = setup_spacecraft!(organization_id, mission_id)

    endpoint =
      persist_source_endpoint!(organization_id, mission_id, spacecraft.spacecraft_id,
        display_name: "Primary"
      )

    revision = persist_imported_revision!(organization_id, mission_id)
    {spacecraft, revision, endpoint}
  end

  def setup_qualified_mission!(organization_id, mission_id) do
    spacecraft = setup_spacecraft!(organization_id, mission_id)

    endpoint =
      persist_source_endpoint!(organization_id, mission_id, spacecraft.spacecraft_id,
        display_name: "Primary"
      )

    revision = persist_qualified_revision!(organization_id, mission_id)
    {spacecraft, revision, endpoint}
  end

  def persist_spacecraft!(organization_id, mission_id, opts) do
    spacecraft =
      Spacecraft.new(%{
        mission_id: mission_id,
        display_name: Keyword.fetch!(opts, :display_name)
      })

    {:ok, persisted} = Cadence.SpacecraftStore.persist_spacecraft(organization_id, spacecraft)
    persisted
  end

  def persist_source_endpoint!(organization_id, mission_id, spacecraft_id, opts) do
    endpoint =
      SourceEndpoint.new(%{
        mission_id: mission_id,
        spacecraft_id: spacecraft_id,
        display_name: Keyword.fetch!(opts, :display_name)
      })

    {:ok, persisted} =
      Cadence.SourceEndpoints.persist_source_endpoint(organization_id, endpoint)

    persisted
  end

  def persist_imported_revision!(organization_id, mission_id, opts \\ []) do
    revision_label = Keyword.get(opts, :revision_label, "Rev 1")
    suffix = Integer.to_string(System.unique_integer([:positive]))

    {:ok, database} =
      Catalog.create_database(organization_id, mission_id, %{
        name: "Bus " <> suffix,
        slug: "bus-" <> suffix,
        catalog_family: :combined,
        default_importer_key: "cadence_yaml"
      })

    yaml =
      Keyword.get(
        opts,
        :yaml,
        """
        packets:
          - name: HEALTH
            apid: 42
            items:
              - name: mode
                data_type: uint
                bit_offset: 0
                bit_size: 8
        commands: []
        """
      )

    artifact =
      Artifact.new(%{
        mission_id: mission_id,
        catalog_database_id: database.catalog_database_id,
        catalog_family: :combined,
        artifact_name: "bus.yaml",
        format_key: "cadence_yaml",
        media_type: "application/yaml",
        source_artifact: yaml
      })

    {:ok, run} =
      Catalog.start_revision_import(
        organization_id,
        mission_id,
        database.catalog_database_id,
        artifact,
        "cadence_yaml",
        metadata: %{"revision_label" => revision_label}
      )

    {:ok, completed} = Catalog.execute_enqueued_run(run.import_run_id)

    {:ok, revision} =
      Catalog.fetch_revision_by_import_run(organization_id, mission_id, completed.import_run_id)

    revision
  end

  def persist_qualified_revision!(organization_id, mission_id, opts \\ []) do
    revision = persist_imported_revision!(organization_id, mission_id, opts)
    qualify_revision!(organization_id, mission_id, revision)
  end

  defp qualify_revision!(organization_id, mission_id, revision) do
    {:ok, _approved_model} =
      Cadence.MissionModels.approve_revision(
        organization_id,
        mission_id,
        revision.mission_model_revision_id,
        %{"kind" => "test_fixture", "id" => "telemetry-decom"}
      )

    {:ok, plans} =
      Cadence.MissionModels.fetch_runtime_plans(
        organization_id,
        mission_id,
        revision.mission_model_revision_id
      )

    {:ok, [packet | _rest]} = MissionModelPlanDecoder.telemetry_packet_definitions(plans)
    [field | _rest] = packet.fields

    update =
      Update.new(%{
        update_id: "telemetry-decom-qualification",
        parameter_id: field.parameter_id,
        qualified_name: field.qualified_name,
        value: 1,
        raw_value: 1,
        quality: :good,
        generation_time: ~U[2026-08-12 12:00:00Z],
        receipt_time: ~U[2026-08-12 12:00:00Z],
        producer_kind: :container,
        producer_id: packet.packet_definition_id,
        metadata: %{mission_id: mission_id}
      })

    {:ok, result, %State{}} =
      SemanticRuntime.process(%State{}, [update], PlanDecoder.decode(plans))

    expected_result_sha256 =
      ContentHash.term_sha256(%{
        updates:
          Enum.map(result.parameter_updates, fn parameter_update ->
            {parameter_update.parameter_id, parameter_update.value, parameter_update.quality,
             parameter_update.generation_time, parameter_update.receipt_time}
          end),
        monitoring:
          Enum.map(result.monitoring_results, fn monitoring ->
            {monitoring.policy_id, monitoring.parameter_id, monitoring.effective_state,
             monitoring.transition}
          end)
      })

    {:ok, _qualification_case} =
      Cadence.MissionModels.register_qualification_case(
        user_scope(organization_id, "qualification"),
        mission_id,
        "Telemetry Decom nominal packet",
        [update],
        expected_result_sha256: expected_result_sha256
      )

    revision
  end

  def user_scope(organization_id, prefix) do
    user_id = "#{prefix}-#{System.unique_integer([:positive])}"

    user =
      User.new(%{
        user_id: user_id,
        email: user_id <> "@example.test",
        display_name: user_id,
        capabilities: [:platform_admin]
      })

    Scope.new(%{user: user, organization_id: organization_id, admin_mode?: true})
  end
end
