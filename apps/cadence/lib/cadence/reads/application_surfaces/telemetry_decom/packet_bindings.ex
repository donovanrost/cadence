defmodule Cadence.Reads.ApplicationSurfaces.TelemetryDecom.PacketBindings do
  @moduledoc "Scoped, paged packet selection and complete saved-selection evidence for Telemetry Decom."

  alias Cadence.Activations

  alias Cadence.Applications.{
    ApplicationInstallations,
    ConfigurationLock,
    HostContext,
    PacketBindings,
    SurfaceQueryRequest,
    TelemetryDecom
  }

  alias Cadence.Applications.TelemetryDecom.Review
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Capabilities.Definitions.DefinitionBoundTelemetry
  alias Cadence.Catalog
  alias Cadence.MissionModels.TelemetryProjection
  alias Cadence.Missions
  alias Cadence.Reads.ApplicationSurfaces.TelemetryDecom.PacketPages, as: Pages
  alias Cadence.SourceEndpoints
  alias Cadence.SpacecraftStore

  def load(
        %Scope{} = scope,
        %HostContext{placement: :spacecraft} = host,
        %SurfaceQueryRequest{
          application_key: "telemetry_decom",
          application_version: 1,
          surface_id: "packet_bindings",
          surface_version: 1,
          query_id: "cadence.packet_bindings.manage",
          query_version: 1,
          params: params
        }
      ) do
    with {:ok, actor_id} <- actor_id(scope),
         {:ok, query} <- Pages.parse(params),
         {:ok, mission} <- Missions.fetch_mission(scope.organization_id, host.mission_id),
         :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: mission.organization_id,
             mission_id: mission.mission_id
           }),
         true <- is_nil(scope.mission_id) or scope.mission_id == host.mission_id,
         {:ok, spacecraft} <-
           SpacecraftStore.fetch_spacecraft(
             scope.organization_id,
             host.mission_id,
             host.spacecraft_id
           ),
         {:ok, installation} <-
           ApplicationInstallations.fetch_installed(scope, host, "telemetry_decom") do
      ConfigurationLock.run(scope.organization_id, host.mission_id, fn ->
        read(scope, host, actor_id, spacecraft.display_name, installation, query)
      end)
    else
      false -> {:error, :invalid_application_scope}
      error -> error
    end
  end

  def load(_, _, _), do: {:error, :unsupported_application_surface_query}

  defp actor_id(%Scope{actor_kind: :user, user: %{user_id: id}}) when is_binary(id), do: {:ok, id}

  defp actor_id(%Scope{actor_kind: :service, service_identity: %{service_identity_id: id}})
       when is_binary(id), do: {:ok, id}

  defp actor_id(_), do: {:error, :unauthorized}

  defp read(scope, host, actor_id, spacecraft_name, installation, query) do
    with {:ok, config} <- optional_config(scope.organization_id, host),
         {:ok, configurations} <-
           PacketBindings.list(scope, host, installation.application_installation_id,
             input_id: "telemetry-fields"
           ),
         {:ok, catalog} <- catalog(scope.organization_id, host.mission_id, config) do
      packet_config = List.first(configurations)

      base =
        "/missions/#{host.mission_id}/spacecraft/#{host.spacecraft_id}/applications/telemetry_decom/packet_bindings"

      [input] = DefinitionBoundTelemetry.descriptor().packet_inputs
      packets = catalog.packets
      selected = selected_ids(packets, config, packet_config)

      available_ids =
        packets |> Enum.filter(&compatible?(&1, input)) |> MapSet.new(& &1.packet_definition_id)

      selected_endpoint_id = selected_endpoint(config, packet_config)
      endpoint = endpoint(scope.organization_id, host, selected_endpoint_id)

      {visible, total, page} =
        packets
        |> Enum.filter(
          &Pages.matches?([&1.packet_definition_id, &1.packet_name, &1.apid], query["q"])
        )
        |> Pages.slice(query, "page")

      endpoint_page = endpoints(scope.organization_id, host, query)

      state = state(scope.organization_id, host.mission_id, config, packet_config)

      data = %{
        "contract_version" => 1,
        "context" => %{
          "organization_id" => scope.organization_id,
          "mission_id" => host.mission_id,
          "spacecraft_id" => host.spacecraft_id,
          "actor_id" => actor_id,
          "installation_id" => installation.application_installation_id
        },
        "spacecraft_name" => spacecraft_name,
        "review_token" =>
          Review.snapshot(scope.organization_id, host.mission_id, host.spacecraft_id)[
            "configuration_token"
          ],
        "query" => Map.put(query, "page", page),
        "configuration" => configuration(config, packet_config, catalog),
        "input" => %{
          "id" => input.input_id,
          "version" => input.version,
          "minimum" => 1,
          "maximum" => 512
        },
        "selection" => %{
          "ids" => Enum.take(selected, 512),
          "total_count" => length(selected),
          "complete" => length(selected) <= 512,
          "unavailable_ids" =>
            selected |> Enum.take(512) |> Enum.reject(&MapSet.member?(available_ids, &1)),
          "endpoint" => endpoint
        },
        "summary" => %{
          "packet_count" => length(packets),
          "selected_count" => length(selected),
          "compatible_packet_count" => MapSet.size(available_ids),
          "selected_field_count" => selected_field_count(packets, selected, input)
        },
        "packets" =>
          Pages.envelope(
            Enum.map(visible, &packet(&1, input, base, query)),
            total,
            page,
            base,
            query,
            "page"
          ),
        "endpoints" =>
          Pages.envelope(
            Enum.map(
              endpoint_page.items,
              &%{"id" => &1.source_endpoint_id, "label" => &1.display_name}
            ),
            endpoint_page.total_count,
            endpoint_page.page,
            base,
            query,
            "endpoint_page"
          ),
        "detail" => detail(packets, input, base, query),
        "status" => state,
        "links" => %{
          "self" => base,
          "manage" => String.replace_suffix(base, "/packet_bindings", "/manage")
        }
      }

      {:ok,
       %{
         "data" => data,
         "navigation" => %{"fallback_href" => data["links"]["manage"], "breadcrumbs" => []}
       }}
    end
  end

  defp endpoints(org, host, query) do
    opts = [
      available_to_spacecraft: host.spacecraft_id,
      search: query["endpoint_q"],
      page: query["endpoint_page"],
      page_size: Pages.size()
    ]

    page = SourceEndpoints.list_source_endpoints_page(org, host.mission_id, opts)
    last = max(1, ceil(page.total_count / Pages.size()))

    if page.page > last do
      SourceEndpoints.list_source_endpoints_page(
        org,
        host.mission_id,
        Keyword.put(opts, :page, last)
      )
    else
      page
    end
  end

  defp optional_config(org, host) do
    case TelemetryDecom.fetch_config(org, host.mission_id, host.spacecraft_id) do
      {:ok, config} -> {:ok, config}
      {:error, :not_configured} -> {:ok, nil}
    end
  end

  defp catalog(_org, _mission, nil), do: {:ok, %{revision: nil, packets: []}}

  defp catalog(org, mission, config) do
    with {:ok, revision} <- Catalog.fetch_revision(org, mission, config.catalog_revision_id),
         {:ok, telemetry} <- TelemetryProjection.load(org, mission, revision) do
      packets =
        telemetry.packet_definitions
        |> Enum.filter(&is_integer(&1.apid))
        |> Enum.sort_by(&{&1.apid, &1.packet_name, &1.packet_definition_id})

      {:ok, %{revision: revision, packets: packets}}
    end
  end

  defp configuration(nil, _, _), do: nil

  defp configuration(config, packet_config, catalog) do
    %{
      "id" => packet_config && packet_config.packet_binding_configuration_id,
      "version" => if(packet_config, do: packet_config.configuration_version, else: 0),
      "catalog_revision_id" => config.catalog_revision_id,
      "catalog_label" => catalog.revision.revision_label,
      "catalog_version" => catalog.revision.revision_number,
      "enabled" => config.enabled
    }
  end

  defp selected_ids(_packets, _config, %{bindings: bindings}),
    do: bindings |> Enum.map(& &1.packet_id) |> Enum.sort()

  defp selected_ids(_packets, nil, _), do: []

  defp selected_ids(packets, config, _) do
    packets
    |> Enum.filter(&(&1.apid in config.handled_apids))
    |> Enum.map(& &1.packet_definition_id)
    |> Enum.sort()
  end

  defp selected_endpoint(nil, _), do: nil
  defp selected_endpoint(_config, %{bindings: [binding | _]}), do: binding.source_endpoint_ref
  defp selected_endpoint(config, _), do: config.source_endpoint_id

  defp endpoint(_org, _host, nil), do: nil

  defp endpoint(org, host, id) do
    case SourceEndpoints.fetch_source_endpoint(org, host.mission_id, id) do
      {:ok, endpoint} when endpoint.spacecraft_id in [nil, host.spacecraft_id] ->
        %{"id" => id, "label" => endpoint.display_name}

      _ ->
        nil
    end
  end

  defp compatible?(packet, input),
    do: Enum.any?(packet.fields, &(&1.data_type in input.accepted_data_types))

  defp selected_field_count(packets, selected, input) do
    packets
    |> Enum.filter(&(&1.packet_definition_id in selected))
    |> Enum.reduce(0, fn packet, count ->
      count + Enum.count(packet.fields, &(&1.data_type in input.accepted_data_types))
    end)
  end

  defp packet(packet, input, base, query) do
    %{
      "id" => packet.packet_definition_id,
      "name" => packet.packet_name,
      "apid" => packet.apid,
      "field_count" => length(packet.fields),
      "compatible_field_count" =>
        Enum.count(packet.fields, &(&1.data_type in input.accepted_data_types)),
      "selectable" => compatible?(packet, input),
      "detail_href" =>
        Pages.href(
          base,
          query |> Map.put("packet", packet.packet_definition_id) |> Map.put("resource_page", 1)
        )
    }
  end

  defp detail(_packets, _input, _base, %{"packet" => ""}), do: nil

  defp detail(packets, input, base, query) do
    case Enum.find(packets, &(&1.packet_definition_id == query["packet"])) do
      nil ->
        %{
          "packet_id" => query["packet"],
          "name" => "Packet unavailable",
          "available" => false,
          "resources" => Pages.envelope([], 0, 1, base, query, "resource_page")
        }

      packet ->
        {fields, total, page} = Pages.slice(packet.fields, query, "resource_page")

        resources =
          Enum.map(
            fields,
            &%{
              "id" => &1.field_id,
              "path" => &1.name,
              "type" => to_string(&1.data_type),
              "size_bits" => &1.size_bits,
              "compatible" => &1.data_type in input.accepted_data_types
            }
          )

        %{
          "packet_id" => packet.packet_definition_id,
          "name" => packet.packet_name,
          "available" => true,
          "resources" => Pages.envelope(resources, total, page, base, query, "resource_page")
        }
    end
  end

  defp state(_org, _mission, nil, _), do: "unconfigured"
  defp state(_org, _mission, %{enabled: false}, _), do: "disabled"
  defp state(_org, _mission, _, %{enabled: false}), do: "disabled"
  defp state(_org, _mission, _, nil), do: "configured"

  defp state(org, mission, config, packets) do
    case Activations.fetch_active_activation(org, mission) do
      {:ok, active} ->
        current? =
          Enum.all?(packets.bindings, &(&1.catalog_revision_id == config.catalog_revision_id)) and
            packets.applied_binding_set_id == active.binding_set_id and
            packets.applied_binding_set_version == active.binding_set_version

        if current?, do: "active", else: "outdated"

      {:error, :no_active_binding_set} ->
        "configured"
    end
  end
end
