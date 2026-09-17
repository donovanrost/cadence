defmodule Cadence.Applications.SpacecraftConfiguration.Active do
  @moduledoc "Reads immutable active spacecraft configurations, including the previous mission-wide basis."

  alias Cadence.Catalog
  alias Cadence.Catalog.SpacecraftConfigurationInput, as: ConfigurationInput
  alias Cadence.Catalog.SpacecraftModelBindings
  alias Cadence.Governance
  alias Cadence.Reads.MissionModels.ActiveBasis
  alias Cadence.SourceEndpoints
  alias Cadence.SpacecraftStore

  def load(mission) do
    case ActiveBasis.fetch_activation(mission.organization_id, mission.mission_id) do
      {:ok, activation} ->
        with {:ok, binding_set} <-
               Governance.fetch_binding_set(
                 mission.organization_id,
                 mission.mission_id,
                 activation.binding_set_id,
                 activation.binding_set_version
               ),
             {:ok, entries} <- entries(mission, activation, binding_set) do
          {:ok, %{activation: activation, binding_set: binding_set, entries: entries}}
        end

      {:error, :no_active_binding_set} ->
        {:ok, %{activation: nil, binding_set: nil, entries: %{}}}
    end
  end

  def source_ids(mission, spacecraft_id) do
    page =
      SourceEndpoints.list_source_endpoints_page(mission.organization_id, mission.mission_id,
        spacecraft_id: spacecraft_id,
        page_size: 100
      )

    if page.total_count <= 100,
      do: {:ok, Enum.map(page.items, & &1.source_endpoint_id) |> Enum.sort()},
      else: {:error, :spacecraft_source_limit_exceeded}
  end

  defp entries(
         _mission,
         %{metadata: %{"spacecraft_configurations" => _} = metadata},
         _binding_set
       ),
       do: SpacecraftModelBindings.entries(metadata)

  defp entries(_mission, %{metadata: metadata}, _binding_set)
       when not is_map_key(metadata, "mission_model"),
       do: {:ok, %{}}

  defp entries(mission, activation, binding_set) do
    model = activation.metadata["mission_model"]

    catalog =
      Enum.find(
        Catalog.list_revisions(mission.organization_id, mission.mission_id),
        &(&1.mission_model_revision_id == model["revision_id"])
      )

    fleet =
      SpacecraftStore.list_spacecraft_page(mission.organization_id, mission.mission_id,
        page_size: 100
      )

    if not is_nil(catalog) and fleet.total_count <= 100 do
      legacy_entries(fleet.items, mission, catalog, model, binding_set)
    else
      {:error, :active_model_catalog_unavailable}
    end
  end

  defp legacy_entries(items, mission, catalog, model, binding_set) do
    Enum.reduce_while(items, {:ok, %{}}, fn spacecraft, {:ok, entries} ->
      case legacy_entry(mission, spacecraft, catalog, model, binding_set) do
        {:ok, nil} -> {:cont, {:ok, entries}}
        {:ok, entry} -> {:cont, {:ok, Map.put(entries, spacecraft.spacecraft_id, entry)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp legacy_entry(mission, spacecraft, catalog, model, binding_set) do
    with {:ok, ids} <- source_ids(mission, spacecraft.spacecraft_id),
         {:ok, profile} <- SpacecraftStore.fetch_pinned_profile(mission, spacecraft) do
      # This namespace is produced by TelemetryDecom.compile_mission_contribution.
      # Preserve other applications' dispatch instances during the transition.
      telemetry =
        Enum.filter(binding_set.capability_instances, fn instance ->
          instance.source_endpoint_ref in ids and
            String.starts_with?(instance.capability_instance_id, "mission_model_telemetry:")
        end)

      document =
        Map.merge(ConfigurationInput.empty(), %{
          "catalog_revision_id" => catalog.catalog_revision_id,
          "commanding_enabled" => true,
          "telemetry_enabled" => telemetry != [],
          "telemetry_source_endpoint_id" =>
            case telemetry do
              [instance | _] -> instance.source_endpoint_ref
              [] -> List.first(ids)
            end,
          "handled_apids" =>
            Enum.map(telemetry, & &1.runtime_configuration.apid) |> Enum.uniq() |> Enum.sort(),
          "protocol" => ConfigurationInput.from_profile(profile)
        })

      entry = %{
        "configuration_revision_id" => nil,
        "configuration_version" => 0,
        "catalog_revision_id" => catalog.catalog_revision_id,
        "commanding_enabled" => true,
        "document" => document,
        "source_endpoint_ids" => ids,
        "mission_model" => model,
        "telemetry_capability_ids" => Enum.map(telemetry, & &1.capability_instance_id)
      }

      {:ok, if(ids == [], do: nil, else: entry)}
    end
  end
end
