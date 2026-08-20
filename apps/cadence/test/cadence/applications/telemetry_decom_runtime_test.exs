defmodule Cadence.Applications.TelemetryDecomRuntimeTest do
  use Cadence.RuntimeCase, async: false

  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Applications.TelemetryDecom
  alias Cadence.Applications.TelemetryDecomFixtures
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Governance
  alias Cadence.Management.Activations, as: ManagementActivations
  alias Cadence.Runtime
  alias Cadence.Runtime.MissionCoordinator

  @organization_id "org-decom-runtime"
  @mission_id "mission-decom-runtime"

  setup do
    on_exit(fn -> Runtime.stop_mission(@mission_id) end)
    :ok
  end

  describe "governed mission apply" do
    test "compiles and activates the mission binding set, stamping each config" do
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

      assert {:ok, applied} =
               apply_mission(
                 @organization_id,
                 @mission_id,
                 spacecraft.spacecraft_id
               )

      assert applied.applied_binding_set_id == TelemetryDecom.binding_set_id(@mission_id)
      assert applied.applied_binding_set_version == 1
      assert %DateTime{} = applied.applied_at
      assert applied.configuration_version == 1

      assert {:ok, activation} =
               Cadence.Activations.fetch_active_activation(@organization_id, @mission_id)

      assert activation.binding_set_id == TelemetryDecom.binding_set_id(@mission_id)
      assert activation.binding_set_version == 1

      assert TelemetryDecom.status(applied, %{
               binding_set_id: activation.binding_set_id,
               binding_set_version: activation.binding_set_version
             }) == :applied
    end

    test "reapplying after a config change bumps the binding set version" do
      {spacecraft, revision, endpoint} = setup_qualified_mission!()

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
        apply_mission(@organization_id, @mission_id, spacecraft.spacecraft_id)

      {:ok, second} =
        apply_mission(@organization_id, @mission_id, spacecraft.spacecraft_id)

      assert second.applied_binding_set_version == 2
    end

    test "refreshes the mission runtime so live partitions see the new binding set" do
      {spacecraft, revision, endpoint} = setup_qualified_mission!()

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
        apply_mission(@organization_id, @mission_id, spacecraft.spacecraft_id)

      assert {:ok, activation} = MissionCoordinator.active_activation(@mission_id)
      assert activation.binding_set_id == TelemetryDecom.binding_set_id(@mission_id)
      assert activation.binding_set_version == 1
    end

    test "disabling the last enabled config activates an empty binding set" do
      {spacecraft, revision, endpoint} = setup_qualified_mission!()

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
        apply_mission(@organization_id, @mission_id, spacecraft.spacecraft_id)

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
               apply_mission(
                 @organization_id,
                 @mission_id,
                 spacecraft.spacecraft_id
               )

      assert {:ok, activation} =
               Cadence.Activations.fetch_active_activation(@organization_id, @mission_id)

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
      {spacecraft, revision, endpoint} = setup_qualified_mission!()

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
        apply_mission(@organization_id, @mission_id, spacecraft.spacecraft_id)

      assert applied.applied_binding_set_id == TelemetryDecom.binding_set_id(@mission_id)

      second_revision = persist_imported_revision!(@mission_id, revision_label: "Rev 2")

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
      {spacecraft, revision, endpoint} = setup_qualified_mission!()

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
        apply_mission(@organization_id, @mission_id, spacecraft.spacecraft_id)

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
        persist_qualified_revision!(@mission_id,
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
        apply_mission(@organization_id, @mission_id, spacecraft.spacecraft_id)

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
      {spacecraft, revision, endpoint} = setup_qualified_mission!()

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
        apply_mission(@organization_id, @mission_id, spacecraft.spacecraft_id)

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

  defp apply_mission(organization_id, mission_id, spacecraft_id) do
    requester = TelemetryDecomFixtures.user_scope(organization_id, "requester")
    approver = TelemetryDecomFixtures.user_scope(organization_id, "approver")

    with {:ok, %{activation_request: request}} <-
           TelemetryDecom.request_mission_apply(requester, mission_id, spacecraft_id),
         {:ok, _request, _decision, approved} <-
           ManagementActivations.approve(
             approver,
             request.activation_request_id,
             "approved in Telemetry Decom test"
           ),
         {:ok, _execution} <- ControlActivations.execute(approved) do
      TelemetryDecom.fetch_config(organization_id, mission_id, spacecraft_id)
    end
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

  defp persist_imported_revision!(mission_id, opts) do
    TelemetryDecomFixtures.persist_imported_revision!(@organization_id, mission_id, opts)
  end

  defp persist_qualified_revision!(mission_id, opts) do
    TelemetryDecomFixtures.persist_qualified_revision!(@organization_id, mission_id, opts)
  end
end
