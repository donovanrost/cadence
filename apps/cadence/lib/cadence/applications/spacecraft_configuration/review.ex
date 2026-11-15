defmodule Cadence.Applications.SpacecraftConfiguration.Review do
  @moduledoc "Builds a reviewed spacecraft change while retaining every other spacecraft's active inputs."

  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Applications.ConfigurationLock
  alias Cadence.Applications.SpacecraftConfiguration.Active, as: ConfigurationActive
  alias Cadence.Applications.SpacecraftConfiguration.CatalogAuthority
  alias Cadence.Applications.SpacecraftConfiguration.Drafts, as: ConfigurationDrafts
  alias Cadence.Applications.TelemetryDecom
  alias Cadence.Applications.TelemetryDecom.Config
  alias Cadence.Catalog
  alias Cadence.Catalog.FleetSnapshot
  alias Cadence.Catalog.SpacecraftModelBindings
  alias Cadence.Governance
  alias Cadence.Management.Activations
  alias Cadence.MissionModels
  alias Cadence.MissionModels.TelemetryProjection
  alias Cadence.Platform.ScopedReadUpdates

  def request(scope, mission_id, spacecraft_id, expected_token, opts \\ []) do
    request_many(scope, mission_id, %{spacecraft_id => expected_token}, opts)
  end

  @max_review_batch SpacecraftModelBindings.max_review_batch()

  @doc "Reviews an exact, bounded set of spacecraft drafts as one governed activation."
  def request_many(scope, mission_id, tokens, opts \\ [])

  def request_many(scope, mission_id, tokens, opts)
      when is_map(tokens) and map_size(tokens) in 1..@max_review_batch do
    {spacecraft_id, _token} = tokens |> Enum.sort() |> hd()

    with {:ok, mission, spacecraft} <-
           ConfigurationDrafts.authorize(scope, mission_id, spacecraft_id) do
      ConfigurationLock.run(
        scope.organization_id,
        mission_id,
        fn ->
          request_locked(scope, mission, spacecraft, tokens, opts)
        end,
        timeout: 120_000
      )
      |> ScopedReadUpdates.publish_result(
        :spacecraft_configuration_changed,
        scope.organization_id,
        mission_id
      )
      |> ScopedReadUpdates.publish_result(:activations_changed, scope.organization_id, mission_id)
    end
  end

  def request_many(_, _, _, _), do: {:error, :spacecraft_configuration_review_unavailable}

  defp request_locked(scope, mission, _spacecraft, tokens, opts) do
    mission_id = mission.mission_id

    with {:ok, active} <- ConfigurationActive.load(mission),
         {:ok, prepared} <- prepare_drafts(scope, mission, tokens),
         binding_set <- replace_contributions(mission, active, prepared),
         {:ok, _} <- Governance.persist_binding_set(scope.organization_id, binding_set),
         entries <- Map.merge(active.entries, Map.new(prepared, &{&1.id, &1.entry})),
         {:ok, fleet} <- FleetSnapshot.store(mission_id, entries),
         metadata <- FleetSnapshot.metadata(fleet, review_evidence(prepared, active)) do
      Activations.request(
        scope,
        mission_id,
        binding_set.binding_set_id,
        binding_set.version,
        Keyword.merge(opts, change_class: :mission_data_plane, metadata: metadata)
      )
    end
  end

  defp prepare_drafts(scope, mission, tokens) do
    tokens
    |> Enum.sort()
    |> Enum.reduce_while({:ok, [], %{}}, fn {id, token}, {:ok, prepared, cache} ->
      with {:ok, _, spacecraft} <- ConfigurationDrafts.authorize(scope, mission.mission_id, id),
           current = ConfigurationDrafts.snapshot(mission, spacecraft),
           :ok <- ConfigurationDrafts.exact_token(current.token, token),
           true <- not is_nil(current.row) and not current.external_changes,
           :ok <- ready(current.row.document),
           :ok <- CatalogAuthority.check(mission, spacecraft, current.row.catalog_revision_id),
           :ok <- CatalogAuthority.switches_check(spacecraft, current.row.document),
           {:ok, inputs, cache} <- cached_inputs(cache, mission, current.row.catalog_revision_id),
           {:ok, item} <- compile(mission, id, current.row, inputs) do
        review = %{
          "spacecraft_id" => id,
          "configuration_revision_id" => current.row.configuration_revision_id,
          "configuration_token" => current.token
        }

        {:cont, {:ok, [Map.put(item, :review, review) | prepared], cache}}
      else
        false -> {:halt, {:error, :spacecraft_configuration_review_unavailable}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, prepared, _cache} -> {:ok, prepared}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  One spacecraft's activation contribution from a configuration revision row: its telemetry
  capability instances and rules, and its fleet entry (catalog, mission model, sources).
  Shared by the per-spacecraft review and change-set catalog generations (DECISIONS #65).
  """
  @spec compile(map(), binary(), struct()) :: {:ok, map()} | {:error, term()}
  def compile(mission, spacecraft_id, row) do
    with {:ok, inputs} <- catalog_inputs(mission, row.catalog_revision_id) do
      compile(mission, spacecraft_id, row, inputs)
    end
  end

  @doc """
  `compile/3` with the catalog's inputs already loaded (`catalog_inputs/2`). A fleet-wide compile
  loads them once per distinct catalog and passes them to every spacecraft on it: step 4 (11-15)
  re-read and re-decoded them for each of 499 spacecraft.
  """
  @spec compile(map(), binary(), struct(), map()) :: {:ok, map()} | {:error, term()}
  def compile(mission, spacecraft_id, row, %{model: model, telemetry: telemetry}) do
    with {:ok, sources} <- ConfigurationActive.source_ids(mission, spacecraft_id),
         true <- sources != [] || {:error, :spacecraft_configuration_review_unavailable},
         {:ok, contribution} <- contribution(mission, spacecraft_id, row, telemetry) do
      {:ok,
       %{
         id: spacecraft_id,
         contribution: contribution,
         entry: entry(row, sources, contribution, model)
       }}
    end
  end

  @doc "The next binding set: the active one with these spacecraft's contributions replaced."
  @spec binding_set(map(), map(), [map()]) :: struct()
  def binding_set(mission, active, items), do: replace_contributions(mission, active, items)

  defp review_evidence([item], active),
    do:
      Map.put(
        item.review,
        "base_activation_id",
        active.activation && active.activation.activation_id
      )

  defp review_evidence(items, active) do
    %{
      "spacecraft_reviews" => Map.new(items, &{&1.id, &1.review}),
      "base_activation_id" => active.activation && active.activation.activation_id
    }
  end

  def ready(%{"catalog_revision_id" => nil}), do: {:error, :spacecraft_catalog_required}

  def ready(%{"telemetry_enabled" => true, "handled_apids" => []}),
    do: {:error, :spacecraft_packet_inputs_required}

  def ready(%{"telemetry_enabled" => true, "telemetry_source_endpoint_id" => nil}),
    do: {:error, :spacecraft_packet_inputs_required}

  def ready(_document), do: :ok

  defp contribution(mission, spacecraft_id, row, telemetry) do
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
      configs,
      telemetry: telemetry
    )
  end

  defp replace_contributions(mission, active, prepared) do
    replaced =
      prepared
      |> Enum.flat_map(fn item ->
        active.entries |> Map.get(item.id, %{}) |> Map.get("telemetry_capability_ids", [])
      end)
      |> MapSet.new()

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
          Enum.flat_map(prepared, & &1.contribution.capability_instances),
      rules:
        Enum.reject(existing_rules, &MapSet.member?(replaced, &1.capability_instance_id)) ++
          Enum.flat_map(prepared, & &1.contribution.rules)
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

  @doc """
  What every spacecraft on `catalog_id` compiles against: `%{model: manifest, telemetry:
  projection}`. Read once (the catalog revision, its mission-model revision and runtime plans) and
  passed explicitly, never memoized in the process dictionary: OpentelemetryEcto copies the whole
  dictionary on every query (step 4, 11-15).
  """
  @spec catalog_inputs(map(), binary()) :: {:ok, map()} | {:error, term()}
  def catalog_inputs(mission, catalog_id) do
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
           ),
         {:ok, telemetry} <- TelemetryProjection.build(catalog, model, plans) do
      {:ok, %{model: MissionModels.manifest(model, plans), telemetry: telemetry}}
    end
  end

  @doc "Inputs for `catalog_id` from `cache`, loading them on the first use: `{:ok, inputs, cache}`."
  @spec cached_inputs(map(), map(), binary()) :: {:ok, map(), map()} | {:error, term()}
  def cached_inputs(cache, mission, catalog_id) do
    case Map.fetch(cache, catalog_id) do
      {:ok, inputs} ->
        {:ok, inputs, cache}

      :error ->
        with {:ok, inputs} <- catalog_inputs(mission, catalog_id),
             do: {:ok, inputs, Map.put(cache, catalog_id, inputs)}
    end
  end
end
