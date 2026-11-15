defmodule Cadence.Applications.TelemetryDecomFixtures do
  @moduledoc false

  alias Cadence.Accounts.User
  alias Cadence.Auth.Scope
  alias Cadence.Catalog
  alias Cadence.Catalog.Artifact
  alias Cadence.MissionModelApproval
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

  @doc """
  A catalog the size of dev's (mission-earendil-demo, rev 4 / model 732618, 11-15): 10 packets with
  dev's field counts (146 fields), 83 of them with limits, and 12 commands. A fleet-scale test on a
  one-packet catalog proved nothing about step 4's apply (director, 11-15).
  """
  def dev_sized_yaml do
    packets =
      Enum.zip([
        ~w(ADCS CCSDS_HDR COMM DEBUG EPS HK PAYLOAD SCIENCE_DATA STRESS_TEST THERM),
        dev_sized_apids(),
        [15, 7, 9, 5, 14, 10, 8, 3, 64, 11]
      ])

    {packet_yaml, _limited} =
      Enum.map_reduce(packets, 0, fn {name, apid, fields}, limited ->
        {items, limited} =
          Enum.map_reduce(0..(fields - 1), limited, &dev_sized_item(name, &1, &2))

        {"  - name: #{name}\n    apid: #{apid}\n    items:\n" <> Enum.join(items), limited}
      end)

    commands =
      for i <- 1..12 do
        "  - name: CMD_#{i}\n    opcode: #{i}\n    parameters:\n      - name: value\n" <>
          "        data_type: uint\n        required: true\n        bit_offset: 0\n        bit_length: 8\n"
      end

    "packets:\n" <> Enum.join(packet_yaml) <> "commands:\n" <> Enum.join(commands)
  end

  defp dev_sized_item(packet, index, limited) do
    limits =
      if limited < 83,
        do: "      limits:\n        yellow_high: 200\n        red_high: 250\n",
        else: ""

    {"      - name: #{String.downcase(packet)}_#{index}\n        data_type: uint\n" <>
       "        bit_offset: #{rem(index, 8) * 8}\n        bit_size: 8\n" <>
       String.replace(limits, "      ", "        "), limited + 1}
  end

  @doc "The apids `dev_sized_yaml/0` declares, in its packet order."
  def dev_sized_apids, do: [30, 2, 40, 255, 20, 1, 50, 100, 101, 10]

  def setup_imported_mission!(organization_id, mission_id, opts \\ []) do
    spacecraft = setup_spacecraft!(organization_id, mission_id)

    endpoint =
      persist_source_endpoint!(organization_id, mission_id, spacecraft.spacecraft_id,
        display_name: "Primary"
      )

    revision = persist_imported_revision!(organization_id, mission_id, opts)
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
        metadata: %{"revision_label" => revision_label},
        requested_by: Keyword.get(opts, :requested_by, %{})
      )

    {:ok, completed} = Catalog.execute_enqueued_run(run.import_run_id)

    {:ok, revision} =
      Catalog.fetch_revision_by_import_run(organization_id, mission_id, completed.import_run_id)

    # Approved, as a catalog a test moves spacecraft onto would be (#92 a's gate); the gate's own
    # tests pass `approve: false`.
    if Keyword.get(opts, :approve, true),
      do:
        MissionModelApproval.approve!(
          organization_id,
          mission_id,
          revision.mission_model_revision_id
        )

    revision
  end

  def persist_qualified_revision!(organization_id, mission_id, opts \\ []) do
    revision = persist_imported_revision!(organization_id, mission_id, opts)
    qualify_revision!(organization_id, mission_id, revision)
  end

  defp qualify_revision!(organization_id, mission_id, revision) do
    {:ok, _approved_model} =
      MissionModelApproval.approve!(
        organization_id,
        mission_id,
        revision.mission_model_revision_id
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
