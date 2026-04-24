defmodule Cadence.Applications.TelemetryDecomTest do
  use Cadence.DataCase, async: false

  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Applications.TelemetryDecom
  alias Cadence.Catalog
  alias Cadence.Catalog.Artifact
  alias Cadence.Governance
  alias Cadence.Runtime
  alias Cadence.Runtime.MissionCoordinator
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft

  @organization_id "org-decom"
  @mission_id "mission-decom"

  setup do
    on_exit(fn -> Runtime.stop_mission(@mission_id) end)
    :ok
  end

  describe "configure/4 and fetch_config/3" do
    test "persists a per-spacecraft configuration and round-trips it" do
      {spacecraft, revision, endpoint} = setup_mission()

      assert {:ok, config} =
               TelemetryDecom.configure(
                 @organization_id,
                 @mission_id,
                 spacecraft.spacecraft_id,
                 catalog_revision_id: revision.catalog_revision_id,
                 handled_apids: [42],
                 source_endpoint_id: endpoint.source_endpoint_id
               )

      assert config.catalog_revision_id == revision.catalog_revision_id
      assert config.handled_apids == [42]
      assert config.source_endpoint_id == endpoint.source_endpoint_id
      assert config.enabled

      assert {:ok, fetched} =
               TelemetryDecom.fetch_config(
                 @organization_id,
                 @mission_id,
                 spacecraft.spacecraft_id
               )

      assert fetched.catalog_revision_id == revision.catalog_revision_id
      assert fetched.handled_apids == [42]

      assert [listed] = TelemetryDecom.list_configs(@organization_id, @mission_id)
      assert listed.spacecraft_id == spacecraft.spacecraft_id
    end

    test "auto-provisions a managed runtime source endpoint when one is not provided" do
      persist_mission_scope(@organization_id, @mission_id)
      spacecraft = persist_spacecraft!(@mission_id, display_name: "Nova-1")
      revision = persist_revision!(@mission_id)

      assert {:ok, config} =
               TelemetryDecom.configure(
                 @organization_id,
                 @mission_id,
                 spacecraft.spacecraft_id,
                 catalog_revision_id: revision.catalog_revision_id,
                 handled_apids: [42]
               )

      assert config.source_endpoint_id == "spacecraft_runtime:#{spacecraft.spacecraft_id}"
      assert config.handled_apids == [42]

      assert {:ok, endpoint} =
               Cadence.fetch_source_endpoint(
                 @organization_id,
                 @mission_id,
                 config.source_endpoint_id
               )

      assert endpoint.spacecraft_id == spacecraft.spacecraft_id
    end

    test "rejects a source endpoint that belongs to a different spacecraft" do
      {spacecraft, revision, _endpoint} = setup_mission()

      other_spacecraft =
        persist_spacecraft!(@mission_id, display_name: "Nova-2")

      other_endpoint =
        persist_source_endpoint!(@mission_id, other_spacecraft.spacecraft_id,
          display_name: "Other"
        )

      assert {:error, :source_endpoint_belongs_to_other_spacecraft} =
               TelemetryDecom.configure(
                 @organization_id,
                 @mission_id,
                 spacecraft.spacecraft_id,
                 catalog_revision_id: revision.catalog_revision_id,
                 handled_apids: [42],
                 source_endpoint_id: other_endpoint.source_endpoint_id
               )
    end

    test "rejects handled APIDs not present in the selected revision" do
      {spacecraft, revision, endpoint} = setup_mission()

      assert {:error, {:handled_apids_not_in_revision, [999]}} =
               TelemetryDecom.configure(
                 @organization_id,
                 @mission_id,
                 spacecraft.spacecraft_id,
                 catalog_revision_id: revision.catalog_revision_id,
                 handled_apids: [999],
                 source_endpoint_id: endpoint.source_endpoint_id
               )
    end

    test "preserves disabled state when editing an existing config" do
      {spacecraft, revision, endpoint} = setup_mission()

      {:ok, _} =
        TelemetryDecom.configure(
          @organization_id,
          @mission_id,
          spacecraft.spacecraft_id,
          catalog_revision_id: revision.catalog_revision_id,
          handled_apids: [42],
          source_endpoint_id: endpoint.source_endpoint_id
        )

      {:ok, disabled} =
        TelemetryDecom.disable(@organization_id, @mission_id, spacecraft.spacecraft_id)

      refute disabled.enabled

      assert {:ok, edited} =
               TelemetryDecom.configure(
                 @organization_id,
                 @mission_id,
                 spacecraft.spacecraft_id,
                 catalog_revision_id: revision.catalog_revision_id,
                 handled_apids: [42],
                 source_endpoint_id: endpoint.source_endpoint_id
               )

      refute edited.enabled
    end
  end

  describe "apply_mission/3" do
    test "compiles and activates the mission binding set, stamping each config" do
      {spacecraft, revision, endpoint} = setup_mission()

      assert {:ok, _config} =
               TelemetryDecom.configure(
                 @organization_id,
                 @mission_id,
                 spacecraft.spacecraft_id,
                 catalog_revision_id: revision.catalog_revision_id,
                 handled_apids: [42],
                 source_endpoint_id: endpoint.source_endpoint_id
               )

      assert {:ok, applied} =
               TelemetryDecom.apply_mission(
                 @organization_id,
                 @mission_id,
                 spacecraft.spacecraft_id
               )

      assert applied.applied_binding_set_id == TelemetryDecom.binding_set_id(@mission_id)
      assert applied.applied_binding_set_version == 1
      assert %DateTime{} = applied.applied_at

      assert {:ok, activation} =
               Cadence.fetch_active_binding_set_activation(@organization_id, @mission_id)

      assert activation.binding_set_id == TelemetryDecom.binding_set_id(@mission_id)
      assert activation.binding_set_version == 1

      assert TelemetryDecom.status(applied, %{
               binding_set_id: activation.binding_set_id,
               binding_set_version: activation.binding_set_version
             }) == :applied
    end

    test "reapplying after a config change bumps the binding set version" do
      {spacecraft, revision, endpoint} = setup_mission()

      {:ok, _} =
        TelemetryDecom.configure(
          @organization_id,
          @mission_id,
          spacecraft.spacecraft_id,
          catalog_revision_id: revision.catalog_revision_id,
          handled_apids: [42],
          source_endpoint_id: endpoint.source_endpoint_id
        )

      {:ok, _} =
        TelemetryDecom.apply_mission(@organization_id, @mission_id, spacecraft.spacecraft_id)

      {:ok, second} =
        TelemetryDecom.apply_mission(@organization_id, @mission_id, spacecraft.spacecraft_id)

      assert second.applied_binding_set_version == 2
    end

    test "refreshes the mission runtime so live partitions see the new binding set" do
      {spacecraft, revision, endpoint} = setup_mission()

      {:ok, _} =
        TelemetryDecom.configure(
          @organization_id,
          @mission_id,
          spacecraft.spacecraft_id,
          catalog_revision_id: revision.catalog_revision_id,
          handled_apids: [42],
          source_endpoint_id: endpoint.source_endpoint_id
        )

      {:ok, _applied} =
        TelemetryDecom.apply_mission(@organization_id, @mission_id, spacecraft.spacecraft_id)

      assert {:ok, activation} = MissionCoordinator.active_activation(@mission_id)
      assert activation.binding_set_id == TelemetryDecom.binding_set_id(@mission_id)
      assert activation.binding_set_version == 1
    end

    test "disabling the last enabled config activates an empty binding set" do
      {spacecraft, revision, endpoint} = setup_mission()

      {:ok, _} =
        TelemetryDecom.configure(
          @organization_id,
          @mission_id,
          spacecraft.spacecraft_id,
          catalog_revision_id: revision.catalog_revision_id,
          handled_apids: [42],
          source_endpoint_id: endpoint.source_endpoint_id
        )

      {:ok, _} =
        TelemetryDecom.apply_mission(@organization_id, @mission_id, spacecraft.spacecraft_id)

      {:ok, _} =
        TelemetryDecom.disable(@organization_id, @mission_id, spacecraft.spacecraft_id)

      assert {:ok, disabled} =
               TelemetryDecom.fetch_config(
                 @organization_id,
                 @mission_id,
                 spacecraft.spacecraft_id
               )

      assert TelemetryDecom.status(disabled, %{
               binding_set_id: TelemetryDecom.binding_set_id(@mission_id),
               binding_set_version: 1
             }) == :outdated

      assert {:ok, _config} =
               TelemetryDecom.apply_mission(
                 @organization_id,
                 @mission_id,
                 spacecraft.spacecraft_id
               )

      assert {:ok, activation} =
               Cadence.fetch_active_binding_set_activation(@organization_id, @mission_id)

      assert activation.binding_set_version == 2

      assert {:ok, %BindingSet{capability_instances: [], rules: []}} =
               Governance.fetch_binding_set(
                 @organization_id,
                 @mission_id,
                 activation.binding_set_id,
                 activation.binding_set_version
               )

      assert {:ok, disabled} =
               TelemetryDecom.fetch_config(
                 @organization_id,
                 @mission_id,
                 spacecraft.spacecraft_id
               )

      assert TelemetryDecom.status(disabled, %{
               binding_set_id: activation.binding_set_id,
               binding_set_version: activation.binding_set_version
             }) == :disabled
    end
  end

  describe "configure/4 after apply_mission" do
    test "clears the applied stamp when catalog_revision_id changes" do
      {spacecraft, revision, endpoint} = setup_mission()

      {:ok, _} =
        TelemetryDecom.configure(
          @organization_id,
          @mission_id,
          spacecraft.spacecraft_id,
          catalog_revision_id: revision.catalog_revision_id,
          handled_apids: [42],
          source_endpoint_id: endpoint.source_endpoint_id
        )

      {:ok, applied} =
        TelemetryDecom.apply_mission(@organization_id, @mission_id, spacecraft.spacecraft_id)

      assert applied.applied_binding_set_id == TelemetryDecom.binding_set_id(@mission_id)

      second_revision = persist_revision!(@mission_id, revision_label: "Rev 2")

      assert {:ok, reconfigured} =
               TelemetryDecom.configure(
                 @organization_id,
                 @mission_id,
                 spacecraft.spacecraft_id,
                 catalog_revision_id: second_revision.catalog_revision_id,
                 handled_apids: [42],
                 source_endpoint_id: endpoint.source_endpoint_id
               )

      assert reconfigured.applied_binding_set_id == nil
      assert reconfigured.applied_binding_set_version == nil
      assert reconfigured.applied_at == nil
    end

    test "clears the applied stamp when source_endpoint_id changes" do
      {spacecraft, revision, endpoint} = setup_mission()

      {:ok, _} =
        TelemetryDecom.configure(
          @organization_id,
          @mission_id,
          spacecraft.spacecraft_id,
          catalog_revision_id: revision.catalog_revision_id,
          handled_apids: [42],
          source_endpoint_id: endpoint.source_endpoint_id
        )

      {:ok, _applied} =
        TelemetryDecom.apply_mission(@organization_id, @mission_id, spacecraft.spacecraft_id)

      other_endpoint =
        persist_source_endpoint!(@mission_id, spacecraft.spacecraft_id, display_name: "Backup")

      assert {:ok, reconfigured} =
               TelemetryDecom.configure(
                 @organization_id,
                 @mission_id,
                 spacecraft.spacecraft_id,
                 catalog_revision_id: revision.catalog_revision_id,
                 handled_apids: [42],
                 source_endpoint_id: other_endpoint.source_endpoint_id
               )

      assert reconfigured.applied_binding_set_id == nil
      assert reconfigured.applied_binding_set_version == nil
      assert reconfigured.applied_at == nil
    end

    test "clears the applied stamp when handled APIDs change" do
      persist_mission_scope(@organization_id, @mission_id)
      spacecraft = persist_spacecraft!(@mission_id, display_name: "Nova-1")

      endpoint =
        persist_source_endpoint!(@mission_id, spacecraft.spacecraft_id, display_name: "Primary")

      revision =
        persist_revision!(@mission_id,
          yaml: """
          packets:
            - name: HEALTH
              apid: 42
              items:
                - name: mode
                  data_type: uint
                  bit_offset: 0
                  bit_size: 8
            - name: EVENTS
              apid: 43
              items:
                - name: event_code
                  data_type: uint
                  bit_offset: 0
                  bit_size: 16
          commands: []
          """
        )

      {:ok, _} =
        TelemetryDecom.configure(
          @organization_id,
          @mission_id,
          spacecraft.spacecraft_id,
          catalog_revision_id: revision.catalog_revision_id,
          handled_apids: [42],
          source_endpoint_id: endpoint.source_endpoint_id
        )

      {:ok, _applied} =
        TelemetryDecom.apply_mission(@organization_id, @mission_id, spacecraft.spacecraft_id)

      assert {:ok, reconfigured} =
               TelemetryDecom.configure(
                 @organization_id,
                 @mission_id,
                 spacecraft.spacecraft_id,
                 catalog_revision_id: revision.catalog_revision_id,
                 handled_apids: [42, 43],
                 source_endpoint_id: endpoint.source_endpoint_id
               )

      assert reconfigured.applied_binding_set_id == nil
      assert reconfigured.applied_binding_set_version == nil
      assert reconfigured.applied_at == nil
    end

    test "preserves the applied stamp when only metadata changes" do
      {spacecraft, revision, endpoint} = setup_mission()

      {:ok, _} =
        TelemetryDecom.configure(
          @organization_id,
          @mission_id,
          spacecraft.spacecraft_id,
          catalog_revision_id: revision.catalog_revision_id,
          handled_apids: [42],
          source_endpoint_id: endpoint.source_endpoint_id
        )

      {:ok, applied} =
        TelemetryDecom.apply_mission(@organization_id, @mission_id, spacecraft.spacecraft_id)

      assert {:ok, reconfigured} =
               TelemetryDecom.configure(
                 @organization_id,
                 @mission_id,
                 spacecraft.spacecraft_id,
                 catalog_revision_id: revision.catalog_revision_id,
                 handled_apids: [42],
                 source_endpoint_id: endpoint.source_endpoint_id,
                 metadata: %{"note" => "unchanged"}
               )

      assert reconfigured.applied_binding_set_id == applied.applied_binding_set_id
      assert reconfigured.applied_binding_set_version == applied.applied_binding_set_version
      assert reconfigured.applied_at == applied.applied_at
    end
  end

  describe "list_revision_apid_rows/3" do
    test "groups snapshot packets by APID and sorts by APID" do
      {_spacecraft, revision, _endpoint} = setup_mission()

      assert {:ok, %{rows: rows, points_by_id: points_by_id}} =
               TelemetryDecom.list_revision_apid_rows(
                 @organization_id,
                 @mission_id,
                 revision.catalog_revision_id
               )

      assert [%{apid: 42, packets: packets, def_count: 1} | _] = rows
      assert [%Cadence.Catalog.Telemetry.Packet{name: "HEALTH", apid: 42}] = packets
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

  describe "list_apid_conflicts/3" do
    test "returns an empty map today — no other applications exist" do
      {spacecraft, _revision, _endpoint} = setup_mission()

      assert TelemetryDecom.list_apid_conflicts(
               @organization_id,
               @mission_id,
               spacecraft.spacecraft_id
             ) == %{}
    end
  end

  defp setup_mission do
    persist_mission_scope(@organization_id, @mission_id)
    spacecraft = persist_spacecraft!(@mission_id, display_name: "Nova-1")

    endpoint =
      persist_source_endpoint!(@mission_id, spacecraft.spacecraft_id, display_name: "Primary")

    revision = persist_revision!(@mission_id)
    {spacecraft, revision, endpoint}
  end

  defp persist_spacecraft!(mission_id, opts) do
    spacecraft =
      Spacecraft.new(%{
        mission_id: mission_id,
        display_name: Keyword.fetch!(opts, :display_name)
      })

    {:ok, persisted} = Cadence.persist_spacecraft(@organization_id, spacecraft)
    persisted
  end

  defp persist_source_endpoint!(mission_id, spacecraft_id, opts) do
    endpoint =
      SourceEndpoint.new(%{
        mission_id: mission_id,
        spacecraft_id: spacecraft_id,
        display_name: Keyword.fetch!(opts, :display_name)
      })

    {:ok, persisted} = Cadence.persist_source_endpoint(@organization_id, endpoint)
    persisted
  end

  defp persist_revision!(mission_id, opts \\ []) do
    revision_label = Keyword.get(opts, :revision_label, "Rev 1")
    suffix = Integer.to_string(System.unique_integer([:positive]))

    {:ok, database} =
      Catalog.create_database(@organization_id, mission_id, %{
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
        @organization_id,
        mission_id,
        database.catalog_database_id,
        artifact,
        "cadence_yaml",
        metadata: %{"revision_label" => revision_label}
      )

    {:ok, completed} = Catalog.execute_enqueued_run(run.import_run_id)

    {:ok, revision} =
      Catalog.fetch_revision_by_import_run(@organization_id, mission_id, completed.import_run_id)

    revision
  end
end
