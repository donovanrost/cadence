defmodule Cadence.Applications.SpacecraftConfiguration.ApplicationInputs do
  @moduledoc "Adapts spacecraft drafts to desired application inputs without confusing applied stamps with edits."

  alias Cadence.MissionModels.TelemetryProjection

  alias Cadence.Applications.ApplicationBindingStore
  alias Cadence.Applications.ApplicationInstallations
  alias Cadence.Applications.HostContext
  alias Cadence.Applications.PacketBindings
  alias Cadence.Applications.TelemetryDecom

  alias Cadence.Platform.ContentHash

  @bookkeeping [
    :applied_binding_set_id,
    :applied_binding_set_version,
    :applied_at,
    :inserted_at,
    :updated_at
  ]

  def basis(mission, spacecraft_id) do
    installations =
      ApplicationInstallations.configuration_basis(
        mission.organization_id,
        mission.mission_id,
        spacecraft_id,
        "telemetry_decom"
      )

    bindings =
      ApplicationBindingStore.list(mission.organization_id, mission.mission_id,
        application_key: "telemetry_decom"
      )
      |> Enum.filter(&(&1.spacecraft_id == spacecraft_id))
      |> Enum.map(&Map.drop(&1, @bookkeeping))
      |> Enum.sort_by(& &1.application_binding_id)

    packets =
      packet_inputs(mission, spacecraft_id)
      |> Enum.map(&canonical_packet_input/1)
      |> Enum.sort_by(& &1.packet_binding_configuration_id)

    ContentHash.term_sha256({1, bindings, packets, installations})
  end

  defp canonical_packet_input(input) do
    input |> Map.drop(@bookkeeping) |> Map.update!(:bindings, &canonical_bindings/1)
  end

  defp canonical_bindings(bindings) do
    bindings
    |> Enum.map(fn binding ->
      %{binding | resources: Enum.sort_by(binding.resources, &{&1.resource_id, &1.path})}
    end)
    |> Enum.sort_by(& &1.packet_binding_id)
  end

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

  defp selection_matches?(input, document) do
    input.enabled == document["telemetry_enabled"] and
      input.bindings |> Enum.map(& &1.apid) |> Enum.uniq() |> Enum.sort() ==
        document["handled_apids"] and
      Enum.all?(
        input.bindings,
        &(&1.catalog_revision_id == document["catalog_revision_id"] and
            &1.source_endpoint_ref == document["telemetry_source_endpoint_id"])
      )
  end

  defp packet_inputs(mission, spacecraft_id) do
    PacketBindings.list_for_mission(mission.organization_id, mission.mission_id,
      application_key: "telemetry_decom"
    )
    |> Enum.filter(&(&1.spacecraft_id == spacecraft_id))
  end
end
