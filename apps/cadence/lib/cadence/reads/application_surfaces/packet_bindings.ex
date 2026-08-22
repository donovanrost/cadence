defmodule Cadence.Reads.ApplicationSurfaces.PacketBindings do
  @moduledoc "Telemetry Decom projection for the host-owned Packet Bindings element."

  @behaviour Cadence.Reads.ApplicationSurfaces.SurfaceQueryProvider

  alias Cadence.Applications.{
    ApplicationInstallations,
    HostContext,
    PacketBindingConfiguration,
    SurfaceDocument,
    SurfaceQueryRequest,
    TelemetryDecom
  }

  alias Cadence.Applications.PacketBindings, as: PacketBindingsContext

  alias Cadence.Applications.SurfaceElements.{
    PacketBindingGroup,
    PacketBindingResource,
    PacketBindings,
    Stat
  }

  alias Cadence.Auth.Scope
  alias Cadence.Capabilities.Definitions.DefinitionBoundTelemetry
  alias Cadence.Catalog
  alias Cadence.Catalog.Revision
  alias Cadence.MissionModels.TelemetryProjection
  alias Cadence.SourceEndpoints

  @max_surface_groups 512
  @max_surface_resources 4_096
  @max_group_resources 256

  @impl true
  def load(
        %Scope{organization_id: organization_id} = current_scope,
        %HostContext{
          placement: :spacecraft,
          mission_id: mission_id,
          spacecraft_id: spacecraft_id
        } = host_context,
        %SurfaceQueryRequest{
          application_key: "telemetry_decom",
          application_version: 1,
          query_id: "cadence.packet_bindings.manage",
          query_version: 1
        }
      )
      when is_binary(organization_id) do
    with {:ok, installation} <-
           ApplicationInstallations.fetch_installed(
             current_scope,
             host_context,
             "telemetry_decom"
           ),
         {:ok, configurations} <-
           PacketBindingsContext.list(
             current_scope,
             host_context,
             installation.application_installation_id,
             input_id: "telemetry-fields"
           ) do
      packet_configuration = List.first(configurations)
      decom_configuration = fetch_decom_configuration(organization_id, mission_id, spacecraft_id)

      {:ok,
       build_document(
         organization_id,
         mission_id,
         spacecraft_id,
         decom_configuration,
         packet_configuration
       )}
    end
  end

  def load(%Scope{}, %HostContext{}, %SurfaceQueryRequest{}),
    do: {:error, :unsupported_application_surface_query}

  defp build_document(
         organization_id,
         mission_id,
         spacecraft_id,
         decom_configuration,
         packet_configuration
       ) do
    input_definition = telemetry_input_definition()
    endpoints = source_endpoints(organization_id, mission_id, spacecraft_id)

    packet_bindings =
      case decom_configuration do
        nil ->
          unavailable_bindings(input_definition, endpoints)

        config ->
          configured_bindings(
            organization_id,
            mission_id,
            config,
            packet_configuration,
            input_definition,
            endpoints
          )
      end

    %SurfaceDocument{
      title: "Telemetry Decom",
      description:
        "Bind governed packet fields to this application. APIDs select packet traffic; they are not exclusive ownership claims.",
      stats: binding_stats(packet_bindings),
      packet_bindings: packet_bindings
    }
  end

  defp unavailable_bindings(input_definition, endpoints) do
    %PacketBindings{
      id: "packet-bindings-surface",
      title: "Packet bindings",
      description:
        "Choose a telemetry catalog revision on Manage before binding packet-model resources.",
      action_id: "save_packet_bindings",
      submit_label: "Save packet bindings",
      input_definition: input_definition,
      source_endpoints: endpoints,
      packet_groups: [],
      activation_state: :unconfigured,
      save_enabled: false,
      empty_title: "Catalog configuration required",
      empty_description:
        "The host needs a configured catalog revision before it can resolve packet fields."
    }
  end

  defp configured_bindings(
         organization_id,
         mission_id,
         config,
         packet_configuration,
         input_definition,
         endpoints
       ) do
    with {:ok, %Revision{} = revision} <-
           Catalog.fetch_revision(
             organization_id,
             mission_id,
             config.catalog_revision_id
           ),
         {:ok, telemetry} <- TelemetryProjection.load(organization_id, mission_id, revision) do
      selected_packet_ids =
        selected_packet_ids(telemetry.packet_definitions, config, packet_configuration)

      binding_matches_revision? =
        binding_configuration_matches_revision?(packet_configuration, config.catalog_revision_id)

      %PacketBindings{
        id: "packet-bindings-surface",
        title: "Packet bindings",
        description:
          "Compatible scalar fields flow into canonical telemetry. Binary regions remain visible in the packet model but are not selected by Decom.",
        action_id: "save_packet_bindings",
        submit_label: "Save packet bindings",
        input_definition: input_definition,
        catalog_revision_id: revision.catalog_revision_id,
        source_endpoint_ref:
          source_endpoint_ref(config, packet_configuration, binding_matches_revision?),
        source_endpoints: endpoints,
        packet_groups:
          packet_groups(
            telemetry.packet_definitions,
            revision,
            input_definition,
            selected_packet_ids,
            source_endpoint_ref(config, packet_configuration, binding_matches_revision?)
          ),
        configured_version: packet_configuration && packet_configuration.configuration_version,
        applied_version: packet_configuration && packet_configuration.applied_binding_set_version,
        activation_state:
          activation_state(config, packet_configuration, binding_matches_revision?),
        save_enabled: true,
        empty_title: "No packet models in this revision",
        empty_description:
          "Import a telemetry catalog containing packet definitions before saving bindings."
      }
    else
      {:error, _reason} ->
        %PacketBindings{
          id: "packet-bindings-surface",
          title: "Packet bindings",
          description: "The configured telemetry packet model is unavailable.",
          action_id: "save_packet_bindings",
          submit_label: "Save packet bindings",
          input_definition: input_definition,
          catalog_revision_id: config.catalog_revision_id,
          source_endpoint_ref: config.source_endpoint_id,
          source_endpoints: endpoints,
          packet_groups: [],
          activation_state: :unavailable,
          save_enabled: false,
          empty_title: "Packet model unavailable",
          empty_description:
            "Return to Manage and select an available telemetry catalog revision."
        }
    end
  end

  defp packet_groups(
         packet_definitions,
         revision,
         input_definition,
         selected_packet_ids,
         source_endpoint_ref
       ) do
    packets =
      packet_definitions
      |> Enum.filter(&is_integer(&1.apid))
      |> Enum.sort_by(fn packet ->
        {not MapSet.member?(selected_packet_ids, packet.packet_definition_id), packet.apid,
         packet.packet_definition_id}
      end)
      |> Enum.take(@max_surface_groups)

    resource_budget =
      min(div(@max_surface_resources, max(length(packets), 1)), @max_group_resources)

    Enum.map(packets, fn packet ->
      selected = MapSet.member?(selected_packet_ids, packet.packet_definition_id)
      resources = resource_rows(packet, input_definition, selected, resource_budget)
      compatible? = compatible_packet?(packet, input_definition)
      resources_truncated? = length(packet.fields) > resource_budget

      %PacketBindingGroup{
        id: packet.packet_definition_id,
        packet_id: packet.packet_definition_id,
        packet_name: packet.packet_name,
        apid: packet.apid,
        selector_summary: "space_packet / #{source_endpoint_ref}",
        model_label: revision.revision_label,
        selected: selected,
        expanded: selected or not compatible?,
        selectable: compatible?,
        state: group_state(selected, compatible?),
        reason: group_reason(compatible?, resources_truncated?, resource_budget),
        consumers: if(selected, do: ["Telemetry Decom"], else: []),
        resources: resources
      }
    end)
  end

  defp compatible_packet?(packet_definition, input_definition) do
    Enum.any?(packet_definition.fields, fn field ->
      :field in input_definition.accepted_resource_kinds and
        field.data_type in input_definition.accepted_data_types
    end)
  end

  defp group_reason(false, _truncated?, _resource_budget),
    do: "This packet has no scalar fields accepted by Telemetry Decom."

  defp group_reason(true, true, resource_budget),
    do: "Showing the first #{resource_budget} resources to keep this surface bounded."

  defp group_reason(true, false, _resource_budget), do: nil

  defp resource_rows(packet_definition, input_definition, selected, resource_budget) do
    packet_definition.fields
    |> Enum.take(resource_budget)
    |> Enum.map(fn field ->
      compatible? =
        :field in input_definition.accepted_resource_kinds and
          field.data_type in input_definition.accepted_data_types

      %PacketBindingResource{
        id: "#{packet_definition.packet_definition_id}:#{field.field_id}",
        resource_id: field.field_id,
        path: field.name,
        resource_kind: if(field.data_type == :binary, do: :binary_region, else: :field),
        data_type: field.data_type,
        size_bits: field.size_bits,
        compatibility: if(compatible?, do: :compatible, else: :incompatible),
        reason: resource_reason(field.data_type, compatible?),
        selected: selected and compatible?,
        role: :primary,
        consumers: if(selected and compatible?, do: ["Telemetry Decom"], else: [])
      }
    end)
  end

  defp resource_reason(_data_type, true), do: nil

  defp resource_reason(:binary, false),
    do: "Binary region retained in the packet model; not emitted as telemetry."

  defp resource_reason(_data_type, false),
    do: "The registered Telemetry Decom input does not accept this field type."

  defp group_state(true, true), do: :selected
  defp group_state(_selected, true), do: :available
  defp group_state(true, false), do: :invalid
  defp group_state(false, false), do: :unavailable

  defp selected_packet_ids(packet_definitions, config, nil) do
    selected_apids = MapSet.new(config.handled_apids)

    packet_definitions
    |> Enum.filter(&MapSet.member?(selected_apids, &1.apid))
    |> MapSet.new(& &1.packet_definition_id)
  end

  defp selected_packet_ids(
         packet_definitions,
         config,
         %PacketBindingConfiguration{} = configuration
       ) do
    if binding_configuration_matches_revision?(configuration, config.catalog_revision_id) do
      MapSet.new(configuration.bindings, & &1.packet_id)
    else
      selected_packet_ids(packet_definitions, config, nil)
    end
  end

  defp binding_configuration_matches_revision?(nil, _catalog_revision_id), do: false

  defp binding_configuration_matches_revision?(configuration, catalog_revision_id) do
    Enum.all?(configuration.bindings, &(&1.catalog_revision_id == catalog_revision_id))
  end

  defp source_endpoint_ref(config, nil, _matches_revision?), do: config.source_endpoint_id

  defp source_endpoint_ref(
         _config,
         %PacketBindingConfiguration{bindings: [binding | _]},
         true
       ),
       do: binding.source_endpoint_ref

  defp source_endpoint_ref(config, %PacketBindingConfiguration{}, _matches_revision?),
    do: config.source_endpoint_id

  defp activation_state(%{enabled: false}, _configuration, _matches_revision?), do: :disabled
  defp activation_state(_config, nil, _matches_revision?), do: :configured

  defp activation_state(_config, %PacketBindingConfiguration{enabled: false}, _matches_revision?),
    do: :disabled

  defp activation_state(_config, %PacketBindingConfiguration{}, false), do: :outdated

  defp activation_state(
         _config,
         %PacketBindingConfiguration{applied_binding_set_id: nil},
         true
       ),
       do: :configured

  defp activation_state(_config, %PacketBindingConfiguration{}, true), do: :active

  defp fetch_decom_configuration(organization_id, mission_id, spacecraft_id) do
    case TelemetryDecom.fetch_config(organization_id, mission_id, spacecraft_id) do
      {:ok, config} -> config
      {:error, :not_configured} -> nil
    end
  end

  defp telemetry_input_definition do
    DefinitionBoundTelemetry.descriptor().packet_inputs
    |> List.first()
  end

  defp source_endpoints(organization_id, mission_id, spacecraft_id) do
    organization_id
    |> SourceEndpoints.list_source_endpoints(mission_id, spacecraft_id: spacecraft_id)
    |> Enum.map(&%{label: &1.display_name, value: &1.source_endpoint_id})
  end

  defp binding_stats(%PacketBindings{} = bindings) do
    selected_count = Enum.count(bindings.packet_groups, & &1.selected)

    resource_count =
      bindings.packet_groups
      |> Enum.filter(& &1.selected)
      |> Enum.flat_map(& &1.resources)
      |> Enum.count(& &1.selected)

    [
      %Stat{
        id: "selected_packets",
        label: "Selected packets",
        value: Integer.to_string(selected_count),
        tone: if(selected_count == 0, do: :attention, else: :ready)
      },
      %Stat{
        id: "selected_resources",
        label: "Scalar resources",
        value: Integer.to_string(resource_count),
        tone: if(resource_count == 0, do: :attention, else: :info)
      },
      %Stat{
        id: "input_sharing",
        label: "Input policy",
        value: "Shared reads",
        tone: :info
      }
    ]
  end
end
