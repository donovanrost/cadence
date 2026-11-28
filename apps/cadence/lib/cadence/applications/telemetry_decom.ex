defmodule Cadence.Applications.TelemetryDecom do
  @moduledoc """
  Spacecraft-centered configuration for the built-in Telemetry Decom
  application.

  Users think in terms of spacecraft and imported catalog revisions.
  This module resolves those choices into the native Mission Model runtime path:

    spacecraft → catalog revision → Mission Model revision → telemetry plan
    → binding set rules → persisted + activated mission binding set

  The application-neutral mission binding set id `"mission_applications:<mission_id>"`
  is shared across all application contributions and spacecraft in a mission.
  Internally each spacecraft config is resolved to
  a managed runtime source endpoint so the dispatcher can disambiguate
  overlapping APIDs across heterogeneous spacecraft.

  The application is headless (#669): it declares no surfaces and no actions, and the console's
  spacecraft configuration and activation screens drive it through
  `Cadence.Applications.SpacecraftConfiguration`.
  """

  alias Cadence.Reads.MissionModels.ActiveBasis

  alias Cadence.Applications.SpacecraftConfiguration.ApplicationInputs,
    as: ConfigurationApplications

  alias Cadence.Applications.SpacecraftConfiguration.Drafts, as: ConfigurationDrafts

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet, CapabilityInstance}
  alias Cadence.Applications.{MissionBindingComposer, MissionBindingContribution}

  alias Cadence.Applications.{
    ApplicationDefinition,
    ConfigurationLock,
    PacketBindings,
    ResourceClaimDefinition,
    ResourceContract
  }

  alias Cadence.Applications.SpacecraftConfiguration.TelemetryDecomProjection
  alias Cadence.Applications.TelemetryDecom.APIDSelection
  alias Cadence.Applications.TelemetryDecom.Config
  alias Cadence.Catalog
  alias Cadence.Catalog.Revision
  alias Cadence.Catalog.TelemetryBinding
  alias Cadence.MissionModels.{SystemSelection, TelemetryProjection}
  alias Cadence.Missions
  alias Cadence.SourceEndpoints
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Telemetry.{FieldDefinition, PacketDefinition}

  @application_key "telemetry_decom"
  @type status :: :not_configured | :configured | :applied | :outdated | :disabled

  @spec application_key() :: binary()
  def application_key, do: @application_key

  @doc "Returns the authoritative Phoenix-owned application definition."
  @spec definition() :: ApplicationDefinition.t()
  def definition do
    %ApplicationDefinition{
      application_key: @application_key,
      version: 1,
      display_name: "Telemetry Decom",
      description: "Bind packet fields and decode selected inputs into named telemetry points.",
      trust: :first_party,
      availability: :available,
      installable_scopes: [:spacecraft],
      configuration_contract: %{
        schema_id: "cadence.telemetry_decom.configuration",
        version: 1
      },
      resource_contract: %ResourceContract{
        claims: [
          %ResourceClaimDefinition{
            claim_type: :packet_apid,
            scope: :spacecraft,
            mode: :shared,
            description:
              "Packet APIDs used to select shared packet-model inputs for this spacecraft application."
          }
        ]
      },
      status_query_id: "cadence.telemetry_decom.status",
      capability_contributions: [
        %{kind: :semantic_handler, family_key: :definition_bound_telemetry}
      ]
    }
  end

  @doc "Validates a governed draft's APIDs and resolves its exact source endpoint."
  def normalize_document(mission, spacecraft, %Revision{} = catalog, document) do
    %{organization_id: org, mission_id: mid} = mission

    with {:ok, telemetry} <- TelemetryProjection.load(org, mid, catalog),
         {:ok, apids} <- APIDSelection.parse(document["handled_apids"]),
         :ok <- validate_handled_apids(telemetry.packet_definitions, apids),
         {:ok, endpoint} <-
           resolve_runtime_source_endpoint_id(
             org,
             mid,
             spacecraft,
             document["telemetry_source_endpoint_id"]
           ) do
      {:ok, %{document | "handled_apids" => apids, "telemetry_source_endpoint_id" => endpoint}}
    end
  end

  @spec fetch_config(binary(), binary(), binary()) ::
          {:ok, Config.t()} | {:error, :not_configured}
  def fetch_config(organization_id, mission_id, spacecraft_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(spacecraft_id) do
    case TelemetryDecomProjection.list(organization_id, mission_id, [spacecraft_id]) do
      [config] -> {:ok, config}
      [] -> {:error, :not_configured}
    end
  end

  @spec list_configs(binary(), binary()) :: [Config.t()]
  def list_configs(organization_id, mission_id) do
    TelemetryDecomProjection.list(organization_id, mission_id)
  end

  @doc "Loads status projections for one bounded spacecraft batch."
  @spec status_configs_for_spacecrafts(binary(), binary(), [binary()]) ::
          {:ok, %{optional(binary()) => Config.t()}} | {:error, :batch_bounds_exceeded}
  def status_configs_for_spacecrafts(organization_id, mission_id, spacecraft_ids)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(spacecraft_ids) do
    ids = Enum.take(spacecraft_ids, 101)

    if length(ids) <= 100 and Enum.all?(ids, &(is_binary(&1) and &1 != "")) do
      configs =
        organization_id
        |> TelemetryDecomProjection.list(mission_id, ids)
        |> Map.new(&{&1.spacecraft_id, &1})

      {:ok, configs}
    else
      {:error, :batch_bounds_exceeded}
    end
  end

  @doc "Records the applied state produced by a spacecraft-configuration activation."
  @spec activation_applied(BindingSet.t(), map() | {:fleet, map()}) :: :ok | {:error, term()}
  def activation_applied(%BindingSet{} = binding_set, {:fleet, entries}) when is_map(entries) do
    ConfigurationLock.run(binding_set.organization_id, binding_set.mission_id, fn ->
      apply_spacecraft_configuration_state(binding_set, entries)
    end)
  end

  def activation_applied(%BindingSet{}, _metadata), do: :ok

  defp apply_spacecraft_configuration_state(binding_set, entries) do
    with {:ok, mission} <-
           Missions.fetch_mission(binding_set.organization_id, binding_set.mission_id),
         {:ok, active} <-
           ActiveBasis.fetch_activation(
             mission.organization_id,
             mission.mission_id
           ),
         true <-
           active.binding_set_id == binding_set.binding_set_id and
             active.binding_set_version == binding_set.version do
      PacketBindings.stamp_applied_for_mission(
        mission.organization_id,
        mission.mission_id,
        binding_set.binding_set_id,
        binding_set.version,
        application_key: @application_key,
        spacecraft_ids: applied_configuration_ids(mission, entries)
      )
    else
      false -> {:error, :spacecraft_configuration_review_stale}
      error -> error
    end
  end

  # The fleet's spacecraft whose latest saved configuration is the one reviewed, on the current
  # application basis. A fixed number of queries for any fleet size: this runs inside the
  # activation's configuration lock, which a 500-spacecraft fleet used to hold past its timeout.
  defp applied_configuration_ids(mission, entries) do
    ids = Map.keys(entries)
    latest = ConfigurationDrafts.latest_many(mission.organization_id, mission.mission_id, ids)
    bases = ConfigurationApplications.bases(mission, Map.keys(latest))

    Enum.flat_map(entries, fn {id, entry} ->
      row = latest[id]

      if row && row.configuration_revision_id == entry["configuration_revision_id"] &&
           row.application_basis == bases[id],
         do: [id],
         else: []
    end)
  end

  @doc """
  Return a high-level state label for a config suitable for user-facing UI.
  """
  @spec status(Config.t() | nil, map() | nil) :: status()
  def status(nil, _active_binding_set_id), do: :not_configured

  def status(%Config{enabled: false} = config, active) do
    if applied_matches_active?(config, active), do: :outdated, else: :disabled
  end

  def status(%Config{applied_binding_set_id: nil}, _active), do: :configured

  def status(%Config{} = config, active) do
    if applied_matches_active?(config, active), do: :applied, else: :outdated
  end

  defp applied_matches_active?(%Config{applied_generation: generation}, %{generation: active})
       when is_integer(active),
       do: generation == active

  defp applied_matches_active?(
         %Config{applied_binding_set_id: applied_id, applied_binding_set_version: applied_ver},
         %{binding_set_id: active_id, binding_set_version: active_ver}
       )
       when is_binary(applied_id) and is_integer(applied_ver) do
    applied_id == active_id and applied_ver == active_ver
  end

  defp applied_matches_active?(%Config{}, _active), do: false

  @doc """
  Resolve the binding set id used for the mission's Telemetry Decom
  configuration.
  """
  @spec binding_set_id(binary()) :: binary()
  def binding_set_id(mission_id) when is_binary(mission_id),
    do: MissionBindingComposer.binding_set_id(mission_id)

  @type apid_row :: %{
          apid: non_neg_integer(),
          packets: [PacketDefinition.t()],
          def_count: non_neg_integer(),
          rate_hz: number() | nil,
          short_description: String.t() | nil
        }

  @type apid_row_result :: %{
          rows: [apid_row()],
          points_by_id: %{optional(binary()) => FieldDefinition.t()}
        }

  @doc """
  Return one row per APID present in the revision's Mission Model telemetry plan.

  Each row carries every lowered packet definition that shares the APID. Rows
  are sorted by APID ascending.

  Also returns a parameter map for looking up human-readable field names.
  """
  @spec list_revision_apid_rows(binary(), binary(), binary()) ::
          {:ok, apid_row_result()} | {:error, term()}
  def list_revision_apid_rows(organization_id, mission_id, catalog_revision_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(catalog_revision_id) do
    with {:ok, %Revision{} = revision} <-
           Catalog.fetch_revision(organization_id, mission_id, catalog_revision_id),
         {:ok, telemetry} <- TelemetryProjection.load(organization_id, mission_id, revision) do
      rows =
        telemetry.packet_definitions
        |> Enum.filter(&is_integer(&1.apid))
        |> Enum.group_by(& &1.apid)
        |> Enum.sort_by(fn {apid, _} -> apid end)
        |> Enum.map(fn {apid, packets} ->
          %{
            apid: apid,
            packets: packets,
            def_count: length(packets),
            rate_hz: nil,
            short_description: nil
          }
        end)

      points_by_id =
        telemetry.packet_definitions
        |> Enum.flat_map(& &1.fields)
        |> Enum.reject(&is_nil(&1.parameter_id))
        |> Map.new(&{&1.parameter_id, &1})

      {:ok, %{rows: rows, points_by_id: points_by_id}}
    end
  end

  @doc false
  @spec compile_mission_contribution(binary(), binary(), [Config.t()], keyword()) ::
          {:ok, MissionBindingContribution.t()} | {:error, term()}
  def compile_mission_contribution(organization_id, mission_id, configs, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(configs) do
    # `telemetry:` a projection the caller already loaded for these configs' catalog, so a
    # fleet-wide compile reads and decodes it once, not once per spacecraft (step 4, 11-15).
    preloaded = Keyword.get(opts, :telemetry)

    {capability_instances, rules, errors} =
      Enum.reduce(configs, {[], [], []}, fn config, {ci_acc, rule_acc, error_acc} ->
        case telemetry_for_config(organization_id, mission_id, config, preloaded) do
          {:ok, telemetry} ->
            compilation = compile_runtime_artifacts(telemetry, config, 1)

            {
              ci_acc ++ compilation.binding_set.capability_instances,
              rule_acc ++ compilation.binding_set.rules,
              error_acc
            }

          {:error, reason} ->
            {ci_acc, rule_acc, [{config.spacecraft_id, reason} | error_acc]}
        end
      end)

    case errors do
      [] ->
        {:ok,
         %MissionBindingContribution{
           contribution_id: @application_key,
           application_key: @application_key,
           capability_instances: capability_instances,
           rules: rules,
           metadata: %{
             "mission_id" => mission_id,
             "configuration_versions" =>
               Enum.map(
                 configs,
                 &%{
                   "spacecraft_id" => &1.spacecraft_id,
                   "configuration_version" => &1.configuration_version
                 }
               )
           }
         }}

      errors ->
        {:error, {:config_compile_failed, errors}}
    end
  end

  defp telemetry_for_config(
         _organization_id,
         _mission_id,
         %Config{catalog_revision_id: id},
         %{catalog_revision: %{catalog_revision_id: id}} = telemetry
       ),
       do: {:ok, telemetry}

  defp telemetry_for_config(organization_id, mission_id, config, _preloaded),
    do: fetch_telemetry_for_config(organization_id, mission_id, config)

  defp fetch_telemetry_for_config(organization_id, mission_id, %Config{} = config) do
    with {:ok, %Revision{} = revision} <-
           Catalog.fetch_revision(organization_id, mission_id, config.catalog_revision_id) do
      TelemetryProjection.load(organization_id, mission_id, revision)
    end
  end

  defp compile_runtime_artifacts(telemetry, %Config{} = config, binding_set_version) do
    packet_definitions = selected_packets(telemetry.packet_definitions, config.handled_apids)

    capability_instances =
      Enum.map(packet_definitions, fn packet_definition ->
        CapabilityInstance.new(%{
          capability_instance_id:
            TelemetryBinding.capability_instance_id(
              telemetry.mission_model_revision.revision_id,
              config.source_endpoint_id,
              packet_definition.packet_definition_id
            ),
          family_key: :definition_bound_telemetry,
          target_scope: :source_endpoint,
          source_endpoint_ref: config.source_endpoint_id,
          runtime_configuration: packet_definition
        })
      end)

    rules =
      Enum.map(capability_instances, fn capability_instance ->
        packet_definition = capability_instance.runtime_configuration

        BindingRule.new(%{
          binding_rule_id: TelemetryBinding.rule_id(capability_instance.capability_instance_id),
          capability_instance_id: capability_instance.capability_instance_id,
          selector: %{
            scope: %{
              target_scope: :source_endpoint,
              source_endpoint_ref: config.source_endpoint_id
            },
            match: %{packet_kind: :space_packet, apid: packet_definition.apid}
          },
          priority: 100,
          fanout_mode: :exclusive
        })
      end)

    %{
      mission_model_revision: telemetry.mission_model_revision,
      telemetry_plan: telemetry.telemetry_plan,
      compiler_result: %{
        packet_definitions: packet_definitions,
        diagnostics: telemetry.telemetry_plan.diagnostics
      },
      binding_set:
        BindingSet.new(%{
          binding_set_id:
            "mission_model_telemetry:#{telemetry.mission_model_revision.revision_id}:#{config.source_endpoint_id}",
          organization_id: telemetry.mission_model_revision.organization_id,
          mission_id: telemetry.mission_model_revision.mission_id,
          version: binding_set_version,
          capability_instances: capability_instances,
          rules: rules
        })
    }
  end

  defp validate_handled_apids(packet_definitions, handled_apids) do
    available_apids = MapSet.new(all_packet_apids(packet_definitions))
    unknown_apids = Enum.reject(handled_apids, &MapSet.member?(available_apids, &1))

    case unknown_apids do
      [] -> :ok
      _unknown_apids -> {:error, {:handled_apids_not_in_revision, Enum.sort(unknown_apids)}}
    end
  end

  defp selected_packets(packet_definitions, handled_apids),
    do: SystemSelection.select(packet_definitions, {:apids, handled_apids})

  defp all_packet_apids(packet_definitions) do
    packet_definitions
    |> Enum.map(& &1.apid)
    |> Enum.filter(&is_integer/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp ensure_endpoint_matches_spacecraft(%SourceEndpoint{spacecraft_id: nil}, _spacecraft_id),
    do: :ok

  defp ensure_endpoint_matches_spacecraft(
         %SourceEndpoint{spacecraft_id: spacecraft_id},
         spacecraft_id
       ),
       do: :ok

  defp ensure_endpoint_matches_spacecraft(
         %SourceEndpoint{spacecraft_id: _other},
         _spacecraft_id
       ),
       do: {:error, :source_endpoint_belongs_to_other_spacecraft}

  defp resolve_runtime_source_endpoint_id(
         organization_id,
         mission_id,
         spacecraft,
         source_endpoint_id
       )
       when is_binary(source_endpoint_id) do
    with {:ok, %SourceEndpoint{} = endpoint} <-
           SourceEndpoints.fetch_source_endpoint(
             organization_id,
             mission_id,
             source_endpoint_id
           ),
         :ok <- ensure_endpoint_matches_spacecraft(endpoint, spacecraft.spacecraft_id) do
      {:ok, endpoint.source_endpoint_id}
    end
  end

  defp resolve_runtime_source_endpoint_id(organization_id, _mission_id, spacecraft, nil) do
    case SourceEndpoints.list_source_endpoints(
           organization_id,
           spacecraft.mission_id,
           spacecraft_id: spacecraft.spacecraft_id
         ) do
      [%SourceEndpoint{} = endpoint] ->
        {:ok, endpoint.source_endpoint_id}

      [] ->
        create_managed_runtime_source_endpoint(organization_id, spacecraft)

      endpoints ->
        case Enum.find(endpoints, &managed_runtime_source_endpoint?/1) do
          %SourceEndpoint{} = endpoint -> {:ok, endpoint.source_endpoint_id}
          nil -> {:error, :spacecraft_runtime_scope_ambiguous}
        end
    end
  end

  defp create_managed_runtime_source_endpoint(organization_id, spacecraft) do
    case SourceEndpoints.ensure_managed_source_endpoint(organization_id, spacecraft) do
      {:ok, persisted} -> {:ok, persisted.source_endpoint_id}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  # Also Readiness's rule for which endpoint carries a spacecraft's telemetry (L22).
  def managed_runtime_source_endpoint?(%SourceEndpoint{} = endpoint) do
    endpoint.source_endpoint_id ==
      SourceEndpoints.managed_source_endpoint_id(endpoint.spacecraft_id) or
      Map.get(endpoint.metadata, "managed_by") == "telemetry_decom"
  end
end
