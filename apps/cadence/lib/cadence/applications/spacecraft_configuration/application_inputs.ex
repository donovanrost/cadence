defmodule Cadence.Applications.SpacecraftConfiguration.ApplicationInputs do
  @moduledoc "Adapts spacecraft drafts to desired application inputs without confusing applied stamps with edits."

  alias Cadence.MissionModels.TelemetryProjection

  alias Cadence.Applications.ApplicationBindingStore
  alias Cadence.Applications.ApplicationInstallations
  alias Cadence.Applications.HostContext

  alias Cadence.Applications.{
    ApplicationBinding,
    PacketBinding,
    PacketBindingConfiguration,
    PacketBindingResource
  }

  alias Cadence.Applications.PacketBindings
  alias Cadence.Applications.TelemetryDecom

  alias Cadence.Platform.ContentBasis

  @basis_version 1
  @basis_fields %{
    ApplicationBinding => [
      :application_binding_id,
      :application_key,
      :catalog_revision_id,
      :configuration_version,
      :enabled,
      :handled_apids,
      :metadata,
      :mission_id,
      :organization_id,
      :source_endpoint_id,
      :spacecraft_id
    ],
    PacketBindingConfiguration => [
      :application_installation_id,
      :application_key,
      :application_version,
      :bindings,
      :capability_family_key,
      :configuration_version,
      :enabled,
      :input_id,
      :input_version,
      :metadata,
      :mission_id,
      :organization_id,
      :packet_binding_configuration_id,
      :spacecraft_id
    ],
    PacketBinding => [
      :apid,
      :catalog_revision_id,
      :metadata,
      :mission_model_revision_id,
      :packet_binding_id,
      :packet_id,
      :packet_model_content_sha256,
      :packet_name,
      :resources,
      :selector,
      :source_endpoint_ref
    ],
    PacketBindingResource => [
      :data_type,
      :metadata,
      :offset_bits,
      :packet_binding_resource_id,
      :path,
      :resource_id,
      :resource_kind,
      :role,
      :size_bits
    ]
  }

  @doc false
  def basis_struct_fields, do: @basis_fields

  def basis(mission, spacecraft_id),
    do: mission |> bases([spacecraft_id]) |> Map.fetch!(spacecraft_id)

  @doc """
  `basis/2` for many spacecraft in a fixed number of queries (`%{spacecraft_id => basis}`), so a
  fleet activation doesn't reload the mission's bindings once per spacecraft.
  """
  def bases(_mission, []), do: %{}

  def bases(mission, spacecraft_ids) when is_list(spacecraft_ids) do
    %{organization_id: org, mission_id: mission_id} = mission

    installations =
      ApplicationInstallations.configuration_bases(
        org,
        mission_id,
        spacecraft_ids,
        "telemetry_decom"
      )

    bindings =
      org
      |> ApplicationBindingStore.list(mission_id,
        application_key: "telemetry_decom",
        spacecraft_ids: spacecraft_ids
      )
      |> Enum.group_by(& &1.spacecraft_id)

    packets =
      org
      |> PacketBindings.list_for_mission(mission_id,
        application_key: "telemetry_decom",
        spacecraft_ids: spacecraft_ids
      )
      |> Enum.group_by(& &1.spacecraft_id)

    Map.new(spacecraft_ids, fn id ->
      {id,
       basis_hash(
         Map.get(bindings, id, []),
         Map.get(packets, id, []),
         Map.get(installations, id, [])
       )}
    end)
  end

  defp basis_hash(bindings, packets, installations) do
    bindings =
      bindings
      |> Enum.sort_by(& &1.application_binding_id)
      |> Enum.map(&basis_value/1)

    packets =
      packets
      |> Enum.map(&canonical_packet_input/1)
      |> Enum.sort_by(& &1.packet_binding_configuration_id)
      |> Enum.map(&basis_value/1)

    # Sorted here, not by the query: a database's text collation mustn't move the hash (#56).
    installations =
      installations
      |> Enum.sort()
      |> Enum.map(fn {id, version, lifecycle_state} ->
        %{installation_id: id, version: version, lifecycle_state: lifecycle_state}
      end)

    ContentBasis.digest("configuration_inputs", @basis_version,
      bindings: bindings,
      packets: packets,
      installations: installations
    )
  end

  defp canonical_packet_input(input) do
    %{input | bindings: canonical_bindings(input.bindings)}
  end

  defp canonical_bindings(bindings) do
    bindings
    |> Enum.map(fn binding ->
      %{binding | resources: Enum.sort_by(binding.resources, &{&1.resource_id, &1.path})}
    end)
    |> Enum.sort_by(& &1.packet_binding_id)
  end

  defp basis_value(%module{} = value) do
    fields = Map.fetch!(@basis_fields, module)
    value |> ContentBasis.project(fields) |> basis_value()
  end

  defp basis_value(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {key, basis_value(value)} end)

  defp basis_value(list) when is_list(list), do: Enum.map(list, &basis_value/1)
  defp basis_value(other), do: other

  def persist(scope, mission, spacecraft, %{"catalog_revision_id" => nil} = document) do
    with :ok <- disable_existing(scope, mission, spacecraft) do
      {:ok,
       %{
         document
         | "telemetry_enabled" => false,
           "commanding_enabled" => false,
           "handled_apids" => []
       }}
    end
  end

  def persist(scope, mission, spacecraft, document) do
    with {:ok, installation} <-
           installation(scope, mission, spacecraft, document["telemetry_enabled"]),
         {:ok, config} <-
           TelemetryDecom.configure(
             scope.organization_id,
             mission.mission_id,
             spacecraft.spacecraft_id,
             %{
               catalog_revision_id: document["catalog_revision_id"],
               enabled: document["telemetry_enabled"],
               handled_apids: document["handled_apids"],
               source_endpoint_id: document["telemetry_source_endpoint_id"]
             }
           ),
         document = Map.put(document, "telemetry_source_endpoint_id", config.source_endpoint_id),
         :ok <- sync_existing_packets(scope, mission, spacecraft, installation, document) do
      {:ok, document}
    end
  end

  defp installation(scope, mission, spacecraft, enabled) do
    host = HostContext.spacecraft(mission.mission_id, spacecraft.spacecraft_id)

    case ApplicationInstallations.fetch_installed(scope, host, "telemetry_decom") do
      {:ok, installation} -> {:ok, installation}
      {:error, _} when enabled -> ApplicationInstallations.install(scope, host, "telemetry_decom")
      {:error, _} -> {:ok, nil}
    end
  end

  defp disable_existing(scope, mission, spacecraft) do
    case TelemetryDecom.fetch_config(
           scope.organization_id,
           mission.mission_id,
           spacecraft.spacecraft_id
         ) do
      {:ok, _} ->
        with {:ok, _} <-
               TelemetryDecom.disable(
                 scope.organization_id,
                 mission.mission_id,
                 spacecraft.spacecraft_id
               ) do
          disable_packets(scope, mission, spacecraft)
        end

      {:error, :not_configured} ->
        :ok
    end
  end

  defp disable_packets(scope, mission, spacecraft) do
    host = HostContext.spacecraft(mission.mission_id, spacecraft.spacecraft_id)

    case ApplicationInstallations.fetch_installed(scope, host, "telemetry_decom") do
      {:ok, installation} ->
        case PacketBindings.disable(scope, host, installation.application_installation_id) do
          {:ok, _} -> :ok
          error -> error
        end

      {:error, _} ->
        :ok
    end
  end

  defp sync_existing_packets(_scope, _mission, _spacecraft, nil, _document), do: :ok

  defp sync_existing_packets(scope, mission, spacecraft, installation, document) do
    inputs = packet_inputs(mission, spacecraft.spacecraft_id)

    Enum.reduce_while(inputs, :ok, fn input, :ok ->
      sync_packet_input(input, scope, mission, spacecraft, installation, document)
    end)
  end

  defp sync_packet_input(input, scope, mission, spacecraft, installation, document) do
    if selection_matches?(input, document) do
      {:cont, :ok}
    else
      with {:ok, revision} <-
             Cadence.Catalog.fetch_revision(
               scope.organization_id,
               mission.mission_id,
               document["catalog_revision_id"]
             ),
           {:ok, telemetry} <-
             TelemetryProjection.load(
               scope.organization_id,
               mission.mission_id,
               revision
             ),
           packets =
             telemetry.packet_definitions
             |> Enum.filter(&(&1.apid in document["handled_apids"]))
             |> Enum.map(& &1.packet_definition_id),
           {:ok, _} <-
             PacketBindings.replace(
               scope,
               HostContext.spacecraft(mission.mission_id, spacecraft.spacecraft_id),
               installation.application_installation_id,
               %{
                 input_id: input.input_id,
                 input_version: input.input_version,
                 expected_configuration_version: input.configuration_version,
                 catalog_revision_id: document["catalog_revision_id"],
                 source_endpoint_ref: document["telemetry_source_endpoint_id"],
                 selected_packet_ids: packets,
                 enabled: document["telemetry_enabled"]
               }
             ) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end
  end

  @doc """
  After a change-set apply derived `rows` (configuration revisions), re-points each of their
  spacecraft's packet inputs whose selection no longer matches the new document, as a Save does
  (`sync_existing_packets/5`), from the per-catalog inputs the apply already loaded (`cache`,
  `Review.cached_inputs/3`): one read of the inputs, no per-spacecraft catalog decode (11-15).
  """
  @spec resync_packet_inputs(map(), [struct()], map()) :: :ok | {:error, term()}
  def resync_packet_inputs(_mission, [], _cache), do: :ok

  def resync_packet_inputs(mission, rows, cache) do
    documents = Map.new(rows, &{&1.spacecraft_id, &1.document})

    replacements =
      mission.organization_id
      |> PacketBindings.list_for_mission(mission.mission_id,
        application_key: "telemetry_decom",
        spacecraft_ids: Map.keys(documents)
      )
      |> Enum.reject(&selection_matches?(&1, documents[&1.spacecraft_id]))
      |> Enum.map(fn input ->
        document = documents[input.spacecraft_id]
        replacement(input, document, cache[document["catalog_revision_id"]])
      end)

    PacketBindings.resync_many(mission.organization_id, mission.mission_id, replacements)
  end

  defp replacement(input, _document, nil), do: {input, %{}, nil}

  defp replacement(input, document, %{telemetry: telemetry}) do
    packets =
      for packet <- telemetry.packet_definitions,
          packet.apid in document["handled_apids"],
          do: packet.packet_definition_id

    {input,
     %{
       input_id: input.input_id,
       input_version: input.input_version,
       expected_configuration_version: input.configuration_version,
       catalog_revision_id: document["catalog_revision_id"],
       source_endpoint_ref: document["telemetry_source_endpoint_id"],
       selected_packet_ids: packets,
       enabled: document["telemetry_enabled"]
     }, telemetry}
  end

  defp selection_matches?(input, document) do
    input.enabled == document["telemetry_enabled"] and
      input.bindings |> Enum.map(& &1.apid) |> Enum.uniq() |> Enum.sort() ==
        (document["handled_apids"] || []) |> Enum.uniq() |> Enum.sort() and
      Enum.all?(
        input.bindings,
        &(&1.catalog_revision_id == document["catalog_revision_id"] and
            &1.source_endpoint_ref == document["telemetry_source_endpoint_id"])
      )
  end

  defp packet_inputs(mission, spacecraft_id) do
    PacketBindings.list_for_mission(mission.organization_id, mission.mission_id,
      application_key: "telemetry_decom",
      spacecraft_ids: [spacecraft_id]
    )
  end
end
