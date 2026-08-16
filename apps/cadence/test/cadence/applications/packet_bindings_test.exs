defmodule Cadence.Applications.PacketBindingsTest do
  use Cadence.DataCase, async: false

  alias Cadence.Applications.{
    ApplicationInstallations,
    HostContext,
    PacketBindings,
    TelemetryDecom
  }

  alias Cadence.Auth.Scope
  alias Cadence.Catalog
  alias Cadence.Catalog.Artifact
  alias Cadence.MissionModels.TelemetryProjection
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft

  @organization_id "org-packet-bindings"
  @mission_id "mission-packet-bindings"
  @spacecraft_id "spacecraft-packet-bindings"

  setup do
    persist_mission_scope(@organization_id, @mission_id)

    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: @spacecraft_id,
        mission_id: @mission_id,
        display_name: "Packet Binding Test Spacecraft"
      })

    assert {:ok, _spacecraft} =
             Cadence.SpacecraftStore.persist_spacecraft(@organization_id, spacecraft)

    endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "source-packet-bindings",
        mission_id: @mission_id,
        spacecraft_id: @spacecraft_id,
        display_name: "Primary Downlink"
      })

    assert {:ok, endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(@organization_id, endpoint)

    revision = persist_revision!()

    {:ok, telemetry} = TelemetryProjection.load(@organization_id, @mission_id, revision)

    scope = %Scope{
      actor_kind: :user,
      organization_id: @organization_id,
      user: %{user_id: "packet-binding-operator"},
      organization_membership: %{lifecycle_state: :active}
    }

    host_context = HostContext.spacecraft(@mission_id, @spacecraft_id)

    assert {:ok, installation} =
             ApplicationInstallations.install(scope, host_context, "telemetry_decom")

    %{
      scope: scope,
      host_context: host_context,
      installation: installation,
      endpoint: endpoint,
      revision: revision,
      telemetry: telemetry,
      packet: List.first(telemetry.packet_definitions)
    }
  end

  test "replaces exact catalog packet resources with optimistic versioning", context do
    attrs = binding_attrs(context)

    assert {:ok, configuration} =
             PacketBindings.replace(
               context.scope,
               context.host_context,
               context.installation.application_installation_id,
               attrs
             )

    assert configuration.configuration_version == 1
    assert configuration.application_key == "telemetry_decom"
    assert configuration.input_id == "telemetry-fields"
    assert configuration.enabled

    assert [binding] = configuration.bindings
    assert binding.packet_id == context.packet.packet_definition_id
    assert binding.apid == 42
    assert binding.catalog_revision_id == context.revision.catalog_revision_id
    assert binding.mission_model_revision_id == context.revision.mission_model_revision_id

    assert binding.packet_model_content_sha256 ==
             context.telemetry.mission_model_revision.content_sha256

    assert binding.source_endpoint_ref == context.endpoint.source_endpoint_id
    assert [%{resource_kind: :field, path: "mode", data_type: :uint}] = binding.resources

    assert {:ok, [persisted]} =
             PacketBindings.list(
               context.scope,
               context.host_context,
               context.installation.application_installation_id
             )

    assert persisted.configuration_version == 1
    assert persisted.bindings == configuration.bindings

    assert {:ok, unchanged} =
             PacketBindings.replace(
               context.scope,
               context.host_context,
               context.installation.application_installation_id,
               Map.put(attrs, :expected_configuration_version, 1)
             )

    assert unchanged.configuration_version == 1
  end

  test "rejects stale or empty replacement without changing the persisted binding", context do
    attrs = binding_attrs(context)

    assert {:ok, configured} =
             PacketBindings.replace(
               context.scope,
               context.host_context,
               context.installation.application_installation_id,
               attrs
             )

    assert {:error, {:packet_binding_configuration_version_conflict, 0, 1}} =
             PacketBindings.replace(
               context.scope,
               context.host_context,
               context.installation.application_installation_id,
               Map.put(attrs, :expected_configuration_version, 0)
             )

    assert {:error, {:packet_binding_selection_too_small, 1, 0}} =
             PacketBindings.replace(
               context.scope,
               context.host_context,
               context.installation.application_installation_id,
               attrs
               |> Map.put(:expected_configuration_version, 1)
               |> Map.put(:selected_packet_ids, [])
             )

    assert {:ok, [persisted]} =
             PacketBindings.list(
               context.scope,
               context.host_context,
               context.installation.application_installation_id
             )

    assert persisted == configured
  end

  test "disabling keeps desired resources but removes their applied stamp", context do
    assert {:ok, configured} =
             PacketBindings.replace(
               context.scope,
               context.host_context,
               context.installation.application_installation_id,
               binding_attrs(context)
             )

    assert {:ok, [disabled]} =
             PacketBindings.disable(
               context.scope,
               context.host_context,
               context.installation.application_installation_id
             )

    refute disabled.enabled
    assert disabled.configuration_version == configured.configuration_version + 1
    assert disabled.bindings == configured.bindings
    assert disabled.applied_binding_set_id == nil
  end

  test "Telemetry Decom resolves runtime selection, endpoint, and applied state from shared bindings",
       context do
    assert {:ok, _legacy_config} =
             TelemetryDecom.configure(
               @organization_id,
               @mission_id,
               @spacecraft_id,
               catalog_revision_id: context.revision.catalog_revision_id,
               handled_apids: [],
               source_endpoint_id: context.endpoint.source_endpoint_id
             )

    alternate_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "source-packet-bindings-alternate",
        mission_id: @mission_id,
        spacecraft_id: @spacecraft_id,
        display_name: "Alternate Downlink"
      })

    assert {:ok, alternate_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(
               @organization_id,
               alternate_endpoint
             )

    assert {:ok, _configuration} =
             PacketBindings.replace(
               context.scope,
               context.host_context,
               context.installation.application_installation_id,
               binding_attrs(context)
               |> Map.put(:source_endpoint_ref, alternate_endpoint.source_endpoint_id)
             )

    assert {:ok, configured} =
             TelemetryDecom.fetch_config(@organization_id, @mission_id, @spacecraft_id)

    assert configured.handled_apids == [42]
    assert configured.source_endpoint_id == alternate_endpoint.source_endpoint_id
    assert configured.applied_binding_set_id == nil

    assert :ok =
             PacketBindings.stamp_applied_for_mission(
               @organization_id,
               @mission_id,
               "mission_applications:#{@mission_id}",
               3,
               application_key: "telemetry_decom"
             )

    assert {:ok, applied} =
             TelemetryDecom.fetch_config(@organization_id, @mission_id, @spacecraft_id)

    assert applied.applied_binding_set_id == "mission_applications:#{@mission_id}"
    assert applied.applied_binding_set_version == 3
  end

  defp binding_attrs(context) do
    %{
      input_id: "telemetry-fields",
      input_version: 1,
      catalog_revision_id: context.revision.catalog_revision_id,
      source_endpoint_ref: context.endpoint.source_endpoint_id,
      selected_packet_ids: [context.packet.packet_definition_id]
    }
  end

  defp persist_revision! do
    suffix = Integer.to_string(System.unique_integer([:positive]))

    {:ok, database} =
      Catalog.create_database(@organization_id, @mission_id, %{
        name: "Packet bindings #{suffix}",
        slug: "packet-bindings-#{suffix}",
        catalog_family: :combined,
        default_importer_key: "cadence_yaml"
      })

    artifact =
      Artifact.new(%{
        mission_id: @mission_id,
        catalog_database_id: database.catalog_database_id,
        catalog_family: :combined,
        artifact_name: "packet-bindings.yaml",
        format_key: "cadence_yaml",
        media_type: "application/yaml",
        source_artifact: """
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
      })

    {:ok, run} =
      Catalog.start_revision_import(
        @organization_id,
        @mission_id,
        database.catalog_database_id,
        artifact,
        "cadence_yaml",
        metadata: %{"revision_label" => "Packet Bindings Rev 1"}
      )

    {:ok, completed} = Catalog.execute_enqueued_run(run.import_run_id)

    {:ok, revision} =
      Catalog.fetch_revision_by_import_run(
        @organization_id,
        @mission_id,
        completed.import_run_id
      )

    revision
  end
end
