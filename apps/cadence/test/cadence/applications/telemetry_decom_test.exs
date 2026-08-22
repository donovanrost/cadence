defmodule Cadence.Applications.TelemetryDecomTest do
  use Cadence.DataCase, async: true

  alias Cadence.Applications.{
    ActionDispatcher,
    ActionRequest,
    ApplicationBinding,
    ApplicationBindingStore,
    ApplicationDependency,
    ApplicationInstallations,
    ApplicationPreflight,
    HostContext,
    PreflightReport,
    Registry
  }

  alias Cadence.Applications.TelemetryDecom
  alias Cadence.Applications.TelemetryDecomFixtures

  @organization_id "org-decom-data"
  @mission_id "mission-decom-data"

  describe "configure/4 and fetch_config/3" do
    test "persists a per-spacecraft configuration and round-trips it" do
      {spacecraft, revision, endpoint} = setup_imported_mission!()

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
      assert config.configuration_version == 1

      assert {:ok, fetched} =
               TelemetryDecom.fetch_config(
                 @organization_id,
                 @mission_id,
                 spacecraft.spacecraft_id
               )

      assert fetched.catalog_revision_id == revision.catalog_revision_id
      assert fetched.handled_apids == [42]
      assert fetched.configuration_version == 1

      assert [listed] = TelemetryDecom.list_configs(@organization_id, @mission_id)
      assert listed.spacecraft_id == spacecraft.spacecraft_id
    end

    test "auto-provisions a managed runtime source endpoint when one is not provided" do
      spacecraft = setup_spacecraft!()
      revision = persist_imported_revision!(@mission_id)

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
               Cadence.SourceEndpoints.fetch_source_endpoint(
                 @organization_id,
                 @mission_id,
                 config.source_endpoint_id
               )

      assert endpoint.spacecraft_id == spacecraft.spacecraft_id
    end

    test "rejects a source endpoint that belongs to a different spacecraft" do
      {spacecraft, revision, _endpoint} = setup_imported_mission!()

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
      {spacecraft, revision, endpoint} = setup_imported_mission!()

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
      {spacecraft, revision, endpoint} = setup_imported_mission!()

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

    test "increments configuration versions only for semantic configuration changes" do
      {spacecraft, revision, endpoint} = setup_imported_mission!()

      attrs = [
        catalog_revision_id: revision.catalog_revision_id,
        handled_apids: [42],
        source_endpoint_id: endpoint.source_endpoint_id
      ]

      assert {:ok, first} =
               TelemetryDecom.configure(
                 @organization_id,
                 @mission_id,
                 spacecraft.spacecraft_id,
                 attrs
               )

      assert first.configuration_version == 1

      assert {:ok, unchanged} =
               TelemetryDecom.configure(
                 @organization_id,
                 @mission_id,
                 spacecraft.spacecraft_id,
                 attrs
               )

      assert unchanged.configuration_version == 1

      assert {:ok, disabled} =
               TelemetryDecom.disable(
                 @organization_id,
                 @mission_id,
                 spacecraft.spacecraft_id
               )

      assert disabled.configuration_version == 2
    end
  end

  describe "governed mission apply" do
    test "creates a pending request without changing the active runtime basis" do
      {spacecraft, revision, endpoint} = setup_qualified_mission!()

      assert {:ok, _config} =
               TelemetryDecom.configure(
                 @organization_id,
                 @mission_id,
                 spacecraft.spacecraft_id,
                 catalog_revision_id: revision.catalog_revision_id,
                 handled_apids: [42],
                 source_endpoint_id: endpoint.source_endpoint_id
               )

      assert {:ok, %{config: config, activation_request: request}} =
               TelemetryDecom.request_mission_apply(
                 user_scope("requester"),
                 @mission_id,
                 spacecraft.spacecraft_id
               )

      assert request.state == :approval_pending
      assert request.metadata["composition"] == "mission_applications"

      assert [%{"application_key" => "telemetry_decom"}] =
               request.metadata["contributors"]

      assert config.applied_binding_set_id == nil

      assert {:error, :no_active_binding_set} =
               Cadence.Activations.fetch_active_activation(@organization_id, @mission_id)
    end
  end

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

  describe "list_apid_conflicts/3" do
    test "returns enabled APID claims from other applications on the spacecraft" do
      spacecraft = setup_spacecraft!()

      assert {:ok, _binding} =
               ApplicationBindingStore.upsert(
                 ApplicationBinding.new(%{
                   organization_id: @organization_id,
                   mission_id: @mission_id,
                   spacecraft_id: spacecraft.spacecraft_id,
                   application_key: :event_reporting,
                   catalog_revision_id: "catalog-revision-fixture",
                   handled_apids: [42],
                   source_endpoint_id: "source-endpoint-fixture"
                 })
               )

      assert TelemetryDecom.list_apid_conflicts(
               @organization_id,
               @mission_id,
               spacecraft.spacecraft_id
             ) == %{42 => "Event Reporting"}
    end
  end

  describe "activation preflight" do
    test "blocks an unconfigured installation and becomes ready after compilation" do
      {spacecraft, revision, endpoint} = setup_imported_mission!()
      scope = user_scope("preflight-ready")
      host_context = HostContext.spacecraft(@mission_id, spacecraft.spacecraft_id)

      assert {:ok, _installation} =
               ApplicationInstallations.install(scope, host_context, "telemetry_decom")

      assert {:ok, definition} = Registry.fetch_available("telemetry_decom")
      assert {:ok, blocked} = ApplicationPreflight.load(scope, host_context, definition)

      refute PreflightReport.ready?(blocked)
      assert blocked.state == :blocked

      assert Enum.map(blocked.checks, & &1.id) == [
               "configuration",
               "packet-apid-binding",
               "runtime-compilation"
             ]

      assert {:ok, _config} =
               TelemetryDecom.configure(
                 @organization_id,
                 @mission_id,
                 spacecraft.spacecraft_id,
                 catalog_revision_id: revision.catalog_revision_id,
                 handled_apids: [42],
                 source_endpoint_id: endpoint.source_endpoint_id
               )

      assert {:ok, ready} = ApplicationPreflight.load(scope, host_context, definition)
      assert PreflightReport.ready?(ready)
      assert ready.state == :ready
      assert Enum.all?(ready.checks, &(&1.state == :ready))
    end

    test "allows another application to read the same APID" do
      {spacecraft, revision, endpoint} = setup_qualified_mission!()
      scope = user_scope("preflight-conflict")
      host_context = HostContext.spacecraft(@mission_id, spacecraft.spacecraft_id)

      assert {:ok, _installation} =
               ApplicationInstallations.install(scope, host_context, "telemetry_decom")

      assert {:ok, _config} =
               TelemetryDecom.configure(
                 @organization_id,
                 @mission_id,
                 spacecraft.spacecraft_id,
                 catalog_revision_id: revision.catalog_revision_id,
                 handled_apids: [42],
                 source_endpoint_id: endpoint.source_endpoint_id
               )

      assert {:ok, _binding} =
               ApplicationBindingStore.upsert(
                 ApplicationBinding.new(%{
                   organization_id: @organization_id,
                   mission_id: @mission_id,
                   spacecraft_id: spacecraft.spacecraft_id,
                   application_key: :event_reporting,
                   catalog_revision_id: revision.catalog_revision_id,
                   handled_apids: [42],
                   source_endpoint_id: endpoint.source_endpoint_id
                 })
               )

      assert {:ok, definition} = Registry.fetch_available("telemetry_decom")
      assert {:ok, report} = ApplicationPreflight.load(scope, host_context, definition)

      assert %{state: :ready, value: "1 APID"} =
               Enum.find(report.checks, &(&1.id == "packet-apid-binding"))

      request = %ActionRequest{
        application_key: "telemetry_decom",
        application_version: 1,
        action_id: "request_activation"
      }

      assert {:ok, %{activation_request: activation_request}} =
               ActionDispatcher.dispatch(scope, host_context, request)

      assert activation_request.state == :approval_pending
    end

    test "evaluates mission dependencies from a spacecraft host without product coupling" do
      spacecraft = setup_spacecraft!()
      scope = user_scope("preflight-dependency")
      spacecraft_host = HostContext.spacecraft(@mission_id, spacecraft.spacecraft_id)

      dependency = %ApplicationDependency{
        application_key: "derived_telemetry",
        minimum_version: 1,
        scope: :mission,
        description: "A fixture dependency used to prove host-scope resolution."
      }

      assert {:ok, [missing]} =
               ApplicationPreflight.evaluate_dependencies(scope, spacecraft_host, [dependency])

      assert missing.state == :blocked

      assert {:ok, _installation} =
               ApplicationInstallations.install(
                 scope,
                 HostContext.mission(@mission_id),
                 "derived_telemetry"
               )

      assert {:ok, [ready]} =
               ApplicationPreflight.evaluate_dependencies(scope, spacecraft_host, [dependency])

      assert ready.state == :ready
      assert ready.value == "v1"

      advisory = %ApplicationDependency{dependency | minimum_version: 2, required: false}

      assert {:ok, [%{state: :attention}]} =
               ApplicationPreflight.evaluate_dependencies(scope, spacecraft_host, [advisory])
    end
  end

  defp user_scope(prefix), do: TelemetryDecomFixtures.user_scope(@organization_id, prefix)

  defp setup_spacecraft! do
    TelemetryDecomFixtures.setup_spacecraft!(@organization_id, @mission_id)
  end

  defp setup_imported_mission! do
    TelemetryDecomFixtures.setup_imported_mission!(@organization_id, @mission_id)
  end

  defp setup_qualified_mission! do
    TelemetryDecomFixtures.setup_qualified_mission!(@organization_id, @mission_id)
  end

  defp persist_spacecraft!(mission_id, opts) do
    TelemetryDecomFixtures.persist_spacecraft!(@organization_id, mission_id, opts)
  end

  defp persist_source_endpoint!(mission_id, spacecraft_id, opts) do
    TelemetryDecomFixtures.persist_source_endpoint!(
      @organization_id,
      mission_id,
      spacecraft_id,
      opts
    )
  end

  defp persist_imported_revision!(mission_id, opts \\ []) do
    TelemetryDecomFixtures.persist_imported_revision!(@organization_id, mission_id, opts)
  end
end
