defmodule Cadence.Applications.SpacecraftConfiguration.Review do
  @moduledoc "Builds a reviewed spacecraft change while retaining every other spacecraft's active inputs."

  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Applications.ConfigurationLock
  alias Cadence.Applications.SpacecraftConfiguration.Active, as: ConfigurationActive
  alias Cadence.Applications.SpacecraftConfiguration.Drafts, as: ConfigurationDrafts
  alias Cadence.Applications.TelemetryDecom
  alias Cadence.Applications.TelemetryDecom.Config
  alias Cadence.Catalog
  alias Cadence.Governance
  alias Cadence.Management.Activations
  alias Cadence.MissionModels
  alias Cadence.Platform.ScopedReadUpdates

  def request(scope, mission_id, spacecraft_id, expected_token, opts \\ []) do
    with {:ok, mission, spacecraft} <-
           ConfigurationDrafts.authorize(scope, mission_id, spacecraft_id) do
      ConfigurationLock.run(scope.organization_id, mission_id, fn ->
        request_locked(scope, mission, spacecraft, expected_token, opts)
      end)
      |> ScopedReadUpdates.publish_result(
        :spacecraft_configuration_changed,
        scope.organization_id,
        mission_id
      )
    end
  end

  defp request_locked(scope, mission, spacecraft, expected_token, opts) do
    mission_id = mission.mission_id
    spacecraft_id = spacecraft.spacecraft_id
    current = ConfigurationDrafts.snapshot(mission, spacecraft)

    with :ok <- ConfigurationDrafts.exact_token(current.token, expected_token),
         true <- not is_nil(current.row) and not current.external_changes,
         :ok <- ready(current.row.document),
         {:ok, active} <- ConfigurationActive.load(mission),
         {:ok, sources} <- ConfigurationActive.source_ids(mission, spacecraft_id),
         true <- sources != [],
         {:ok, contribution} <- contribution(mission, spacecraft_id, current.row),
         binding_set <- replace_contribution(mission, spacecraft_id, active, contribution),
         {:ok, _} <- Governance.persist_binding_set(scope.organization_id, binding_set),
         {:ok, model} <- model_manifest(mission, current.row.catalog_revision_id),
         entries <-
           Map.put(
             active.entries,
             spacecraft_id,
             entry(current.row, sources, contribution, model)
           ),
         metadata <- %{
           "spacecraft_configuration_version" => 1,
           "spacecraft_configurations" => entries,
           "configuration_review" => %{
             "spacecraft_id" => spacecraft_id,
             "configuration_revision_id" => current.row.configuration_revision_id,
             "configuration_token" => current.token,
             "base_activation_id" => active.activation && active.activation.activation_id
           }
         },
         true <- byte_size(Jason.encode!(metadata)) <= 65_536 do
      Activations.request(
        scope,
        mission_id,
        binding_set.binding_set_id,
        binding_set.version,
        Keyword.merge(opts, change_class: :mission_data_plane, metadata: metadata)
      )
    else
      false -> {:error, :spacecraft_configuration_review_unavailable}
      {:error, reason} -> {:error, reason}
    end
  end

  def ready(%{"catalog_revision_id" => nil}), do: {:error, :spacecraft_catalog_required}

  def ready(%{"telemetry_enabled" => true, "handled_apids" => []}),
    do: {:error, :spacecraft_packet_inputs_required}

  def ready(%{"telemetry_enabled" => true, "telemetry_source_endpoint_id" => nil}),
    do: {:error, :spacecraft_packet_inputs_required}

  def ready(_document), do: :ok

  defp contribution(mission, spacecraft_id, row) do
    document = row.document

    configs =
      if document["telemetry_enabled"] do
        [
          Config.new(%{
            organization_id: mission.organization_id,
            mission_id: mission.mission_id,
            spacecraft_id: spacecraft_id,
            configuration_version: row.version,
            catalog_revision_id: row.catalog_revision_id,
            handled_apids: document["handled_apids"],
            source_endpoint_id: document["telemetry_source_endpoint_id"]
          })
        ]
      else
        []
      end

    TelemetryDecom.compile_mission_contribution(
      mission.organization_id,
      mission.mission_id,
      configs
    )
  end

  defp replace_contribution(mission, spacecraft_id, active, contribution) do
    previous = Map.get(active.entries, spacecraft_id, %{})
    replaced = MapSet.new(Map.get(previous, "telemetry_capability_ids", []))

    existing_instances =
      if active.binding_set, do: active.binding_set.capability_instances, else: []

    existing_rules = if active.binding_set, do: active.binding_set.rules, else: []
    id = TelemetryDecom.binding_set_id(mission.mission_id)

    version =
      case Governance.fetch_latest_binding_set(mission.organization_id, mission.mission_id, id) do
        {:ok, existing} -> existing.version + 1
        {:error, :binding_set_not_found} -> 1
      end

    BindingSet.new(%{
      organization_id: mission.organization_id,
      mission_id: mission.mission_id,
      binding_set_id: id,
      version: version,
      capability_instances:
        Enum.reject(existing_instances, &MapSet.member?(replaced, &1.capability_instance_id)) ++
          contribution.capability_instances,
      rules:
        Enum.reject(existing_rules, &MapSet.member?(replaced, &1.capability_instance_id)) ++
          contribution.rules
    })
  end

  defp entry(row, sources, contribution, model) do
    %{
      "configuration_revision_id" => row.configuration_revision_id,
      "configuration_version" => row.version,
      "catalog_revision_id" => row.catalog_revision_id,
      "commanding_enabled" => row.document["commanding_enabled"],
      "document" => row.document,
      "mission_model" => model,
      "source_endpoint_ids" => sources,
      "telemetry_capability_ids" =>
        Enum.map(contribution.capability_instances, & &1.capability_instance_id)
    }
  end

  defp model_manifest(mission, catalog_id) do
    with {:ok, catalog} <-
           Catalog.fetch_revision(mission.organization_id, mission.mission_id, catalog_id),
         {:ok, model} <-
           MissionModels.fetch_revision(
             mission.organization_id,
             mission.mission_id,
             catalog.mission_model_revision_id
           ),
         {:ok, plans} <-
           MissionModels.fetch_runtime_plans(
             mission.organization_id,
             mission.mission_id,
             model.revision_id
           ) do
      {:ok, MissionModels.manifest(model, plans)}
    end
  end
end
