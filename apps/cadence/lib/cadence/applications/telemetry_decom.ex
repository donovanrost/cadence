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
  """

  import Ecto.Query

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet, CapabilityInstance}
  alias Cadence.Applications.ApplicationBinding
  alias Cadence.Applications.ApplicationBindingStore
  alias Cadence.Applications.ApplicationBindingStore.BindingRow
  alias Cadence.Applications.{MissionBindingComposer, MissionBindingContribution}
  alias Cadence.Applications.{PacketBindingConfiguration, PacketBindings}
  alias Cadence.Applications.TelemetryDecom.APIDSelection
  alias Cadence.Applications.TelemetryDecom.Config
  alias Cadence.Auth.Scope
  alias Cadence.Catalog
  alias Cadence.Catalog.Revision
  alias Cadence.Governance
  alias Cadence.Management.Activations.ActivationRequest
  alias Cadence.MissionModels
  alias Cadence.MissionModels.TelemetryProjection
  alias Cadence.Missions
  alias Cadence.Repo
  alias Cadence.SourceEndpoints
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.SpacecraftStore
  alias Cadence.Telemetry.{FieldDefinition, PacketDefinition}

  @application_key "telemetry_decom"
  @type status :: :not_configured | :configured | :applied | :outdated | :disabled

  @spec configure(binary(), binary(), binary(), map() | keyword()) ::
          {:ok, Config.t()} | {:error, term()}
  def configure(organization_id, mission_id, spacecraft_id, attrs)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(spacecraft_id) and
             is_list(attrs) do
    configure(organization_id, mission_id, spacecraft_id, Map.new(attrs))
  end

  def configure(organization_id, mission_id, spacecraft_id, attrs)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(spacecraft_id) and
             is_map(attrs) do
    with {:ok, config_inputs} <-
           validate_configure_inputs(organization_id, mission_id, spacecraft_id, attrs) do
      upsert_config(organization_id, mission_id, spacecraft_id, attrs, config_inputs)
    end
  end

  defp validate_configure_inputs(organization_id, mission_id, spacecraft_id, attrs) do
    with {:ok, _mission} <- Missions.fetch_mission(organization_id, mission_id),
         {:ok, spacecraft} <-
           SpacecraftStore.fetch_spacecraft(organization_id, mission_id, spacecraft_id),
         {:ok, catalog_revision_id} <- fetch_required(attrs, :catalog_revision_id),
         {:ok, %Revision{} = revision} <-
           Catalog.fetch_revision(organization_id, mission_id, catalog_revision_id),
         {:ok, telemetry} <- TelemetryProjection.load(organization_id, mission_id, revision),
         {:ok, handled_apids} <- parse_handled_apids(attrs),
         :ok <- validate_handled_apids(telemetry.packet_definitions, handled_apids),
         {:ok, source_endpoint_id} <-
           resolve_runtime_source_endpoint_id(
             organization_id,
             mission_id,
             spacecraft,
             fetch_optional(attrs, :source_endpoint_id)
           ) do
      {:ok, %{handled_apids: handled_apids, source_endpoint_id: source_endpoint_id}}
    end
  end

  defp upsert_config(organization_id, mission_id, spacecraft_id, attrs, config_inputs) do
    existing =
      case ApplicationBindingStore.fetch(
             organization_id,
             mission_id,
             spacecraft_id,
             @application_key
           ) do
        {:ok, binding} -> binding
        {:error, :application_binding_not_configured} -> nil
      end

    catalog_revision_id = fetch_attr!(attrs, :catalog_revision_id)
    source_endpoint_id = config_inputs.source_endpoint_id
    handled_apids = config_inputs.handled_apids

    preserved_stamp =
      preserved_applied_stamp(existing, catalog_revision_id, source_endpoint_id, handled_apids)

    enabled = resolve_enabled(attrs, existing)

    config =
      Config.new(%{
        spacecraft_id: spacecraft_id,
        organization_id: organization_id,
        mission_id: mission_id,
        configuration_version: existing && existing.configuration_version,
        catalog_revision_id: catalog_revision_id,
        handled_apids: handled_apids,
        source_endpoint_id: source_endpoint_id,
        enabled: enabled,
        applied_binding_set_id: preserved_stamp.applied_binding_set_id,
        applied_binding_set_version: preserved_stamp.applied_binding_set_version,
        applied_at: preserved_stamp.applied_at,
        metadata: Map.get(attrs, :metadata, %{})
      })

    case ApplicationBindingStore.upsert(config_to_binding(config)) do
      {:ok, binding} ->
        {:ok,
         binding
         |> config_from_binding()
         |> overlay_packet_binding_selection()}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp preserved_applied_stamp(
         %ApplicationBinding{
           catalog_revision_id: catalog_revision_id,
           source_endpoint_id: source_endpoint_id,
           handled_apids: handled_apids
         } = existing,
         catalog_revision_id,
         source_endpoint_id,
         handled_apids
       ) do
    %{
      applied_binding_set_id: existing.applied_binding_set_id,
      applied_binding_set_version: existing.applied_binding_set_version,
      applied_at: existing.applied_at
    }
  end

  defp preserved_applied_stamp(
         _existing_or_nil,
         _catalog_revision_id,
         _source_endpoint_id,
         _handled_apids
       ) do
    %{applied_binding_set_id: nil, applied_binding_set_version: nil, applied_at: nil}
  end

  defp fetch_attr!(attrs, key),
    do: Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))

  defp fetch_optional(attrs, key) do
    case fetch_attr!(attrs, key) do
      value when is_binary(value) and value != "" -> value
      _other -> nil
    end
  end

  defp resolve_enabled(attrs, %ApplicationBinding{} = existing) do
    Map.get(attrs, :enabled, Map.get(attrs, "enabled", existing.enabled))
  end

  defp resolve_enabled(attrs, nil) do
    Map.get(attrs, :enabled, Map.get(attrs, "enabled", true))
  end

  defp config_to_binding(%Config{} = config) do
    ApplicationBinding.new(%{
      application_binding_id: application_binding_id(config.spacecraft_id),
      organization_id: config.organization_id,
      mission_id: config.mission_id,
      spacecraft_id: config.spacecraft_id,
      application_key: @application_key,
      configuration_version: config.configuration_version,
      catalog_revision_id: config.catalog_revision_id,
      handled_apids: config.handled_apids,
      source_endpoint_id: config.source_endpoint_id,
      enabled: config.enabled,
      applied_binding_set_id: config.applied_binding_set_id,
      applied_binding_set_version: config.applied_binding_set_version,
      applied_at: config.applied_at,
      updated_at: config.updated_at,
      metadata: config.metadata
    })
  end

  defp config_from_binding(%ApplicationBinding{} = binding) do
    %Config{
      spacecraft_id: binding.spacecraft_id,
      organization_id: binding.organization_id,
      mission_id: binding.mission_id,
      configuration_version: binding.configuration_version,
      catalog_revision_id: binding.catalog_revision_id,
      handled_apids: binding.handled_apids,
      source_endpoint_id: binding.source_endpoint_id,
      enabled: binding.enabled,
      applied_binding_set_id: binding.applied_binding_set_id,
      applied_binding_set_version: binding.applied_binding_set_version,
      applied_at: binding.applied_at,
      updated_at: binding.updated_at,
      metadata: binding.metadata
    }
  end

  defp overlay_packet_binding_selection(%Config{} = config) do
    configuration =
      config.organization_id
      |> PacketBindings.list_for_mission(config.mission_id,
        application_key: @application_key
      )
      |> Enum.find(&(&1.spacecraft_id == config.spacecraft_id))

    overlay_packet_binding_selection(config, configuration)
  end

  defp overlay_packet_binding_selections(configs, organization_id, mission_id) do
    configurations =
      PacketBindings.list_for_mission(organization_id, mission_id,
        application_key: @application_key
      )
      |> Map.new(&{&1.spacecraft_id, &1})

    Enum.map(configs, fn config ->
      overlay_packet_binding_selection(config, Map.get(configurations, config.spacecraft_id))
    end)
  end

  defp overlay_packet_binding_selection(%Config{} = config, nil), do: config

  defp overlay_packet_binding_selection(
         %Config{} = config,
         %PacketBindingConfiguration{} = configuration
       ) do
    if Enum.all?(configuration.bindings, &(&1.catalog_revision_id == config.catalog_revision_id)) do
      handled_apids =
        configuration.bindings
        |> Enum.map(& &1.apid)
        |> Enum.uniq()
        |> Enum.sort()

      source_endpoint_id =
        case configuration.bindings do
          [binding | _] -> binding.source_endpoint_ref
          [] -> config.source_endpoint_id
        end

      %Config{
        config
        | handled_apids: handled_apids,
          source_endpoint_id: source_endpoint_id,
          enabled: config.enabled and configuration.enabled,
          applied_binding_set_id: configuration.applied_binding_set_id,
          applied_binding_set_version: configuration.applied_binding_set_version,
          applied_at: configuration.applied_at
      }
    else
      config
    end
  end

  defp application_binding_id(spacecraft_id) do
    "application_binding:#{spacecraft_id}:#{@application_key}"
  end

  defp mission_contributors(organization_id, mission_id) do
    packet_binding_contributors =
      organization_id
      |> PacketBindings.list_for_mission(mission_id,
        enabled: true,
        application_key: @application_key
      )
      |> Enum.map(fn configuration ->
        %{
          "application_installation_id" => configuration.application_installation_id,
          "application_key" => configuration.application_key,
          "application_version" => configuration.application_version,
          "input_id" => configuration.input_id,
          "input_version" => configuration.input_version,
          "configuration_version" => configuration.configuration_version
        }
      end)

    if packet_binding_contributors == [] do
      list_configs(organization_id, mission_id)
      |> Enum.filter(& &1.enabled)
      |> Enum.map(fn config ->
        %{
          "application_key" => @application_key,
          "spacecraft_id" => config.spacecraft_id,
          "configuration_version" => config.configuration_version
        }
      end)
    else
      packet_binding_contributors
    end
  end

  @spec fetch_config(binary(), binary(), binary()) ::
          {:ok, Config.t()} | {:error, :not_configured}
  def fetch_config(organization_id, mission_id, spacecraft_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(spacecraft_id) do
    case ApplicationBindingStore.fetch(
           organization_id,
           mission_id,
           spacecraft_id,
           @application_key
         ) do
      {:ok, binding} ->
        {:ok, binding |> config_from_binding() |> overlay_packet_binding_selection()}

      {:error, :application_binding_not_configured} ->
        {:error, :not_configured}
    end
  end

  @spec list_configs(binary(), binary()) :: [Config.t()]
  def list_configs(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    organization_id
    |> ApplicationBindingStore.list(mission_id, application_key: @application_key)
    |> Enum.map(&config_from_binding/1)
    |> overlay_packet_binding_selections(organization_id, mission_id)
  end

  @doc """
  Compile every enabled spacecraft config in the mission into a single merged
  binding set and activate it. Returns the updated config for the spacecraft
  that triggered the apply.
  """
  @spec request_mission_apply(Scope.t(), binary(), binary()) ::
          {:ok, %{config: Config.t(), activation_request: ActivationRequest.t()}}
          | {:error, term()}
  def request_mission_apply(%Scope{} = current_scope, mission_id, triggering_spacecraft_id)
      when is_binary(mission_id) and
             is_binary(triggering_spacecraft_id) do
    organization_id = current_scope.organization_id

    with {:ok, _mission} <- Missions.fetch_mission(organization_id, mission_id),
         {:ok, config} <-
           fetch_config(organization_id, mission_id, triggering_spacecraft_id),
         all_configs <- list_configs(organization_id, mission_id),
         configs <- Enum.filter(all_configs, & &1.enabled),
         {:ok, contribution} <-
           compile_mission_contribution(organization_id, mission_id, configs),
         {:ok, binding_set} <-
           MissionBindingComposer.compose(organization_id, mission_id, [contribution]),
         {:ok, _persisted} <- Governance.persist_binding_set(organization_id, binding_set),
         {:ok, mission_model_revision_id} <-
           mission_model_revision_for_apply(
             organization_id,
             mission_id,
             configs,
             config
           ),
         {:ok, %ActivationRequest{} = activation_request} <-
           MissionModels.request_promotion(
             current_scope,
             mission_id,
             mission_model_revision_id,
             binding_set.binding_set_id,
             binding_set.version,
             metadata: %{
               "composition" => "mission_applications",
               "contributors" => mission_contributors(organization_id, mission_id),
               "triggering_spacecraft_id" => triggering_spacecraft_id
             }
           ) do
      {:ok, %{config: config, activation_request: activation_request}}
    end
  end

  defp mission_model_revision_for_apply(
         organization_id,
         mission_id,
         enabled_configs,
         triggering_config
       ) do
    configs = if enabled_configs == [], do: [triggering_config], else: enabled_configs

    configs
    |> Enum.reduce_while({:ok, MapSet.new()}, fn config, {:ok, revision_ids} ->
      case Catalog.fetch_revision(
             organization_id,
             mission_id,
             config.catalog_revision_id
           ) do
        {:ok, %Revision{} = revision} ->
          {:cont, {:ok, MapSet.put(revision_ids, revision.mission_model_revision_id)}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, revision_ids} ->
        case revision_ids |> MapSet.to_list() |> Enum.sort() do
          [revision_id] ->
            {:ok, revision_id}

          ids ->
            {:error, {:telemetry_decom_requires_one_mission_model_revision, ids}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Records the applied state produced by a governed Telemetry Decom activation."
  @spec activation_applied(BindingSet.t(), map()) :: :ok | {:error, term()}
  def activation_applied(
        %BindingSet{binding_set_id: binding_set_id} = binding_set,
        %{"composition" => "mission_applications"}
      ) do
    if binding_set_id == binding_set_id(binding_set.mission_id) do
      with :ok <-
             binding_set.organization_id
             |> list_configs(binding_set.mission_id)
             |> reconcile_application_state(binding_set) do
        PacketBindings.stamp_applied_for_mission(
          binding_set.organization_id,
          binding_set.mission_id,
          binding_set.binding_set_id,
          binding_set.version,
          application_key: @application_key
        )
      end
    else
      {:error, :telemetry_decom_activation_binding_set_mismatch}
    end
  end

  def activation_applied(
        %BindingSet{} = binding_set,
        %{"application" => @application_key}
      ) do
    activation_applied(binding_set, %{"composition" => "mission_applications"})
  end

  def activation_applied(%BindingSet{}, _metadata), do: :ok

  @doc """
  Disable a spacecraft's Telemetry Decom configuration. The configuration is
  kept so the user can re-enable without re-entering choices, but it will no
  longer contribute rules on the next apply.
  """
  @spec disable(binary(), binary(), binary()) :: {:ok, Config.t()} | {:error, term()}
  def disable(organization_id, mission_id, spacecraft_id) do
    with {:ok, %ApplicationBinding{} = binding} <-
           ApplicationBindingStore.fetch(
             organization_id,
             mission_id,
             spacecraft_id,
             @application_key
           ) do
      case %ApplicationBinding{binding | enabled: false}
           |> ApplicationBindingStore.upsert() do
        {:ok, binding} -> {:ok, config_from_binding(binding)}
        {:error, reason} -> {:error, reason}
      end
    end
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

  @doc """
  Compile the preview runtime artifacts for a single config. Exposed for the
  UI so it can show packet definition counts and diagnostics without applying.
  """
  @spec preview(binary(), binary(), Config.t()) ::
          {:ok,
           %{
             mission_model_revision: Cadence.Catalog.MissionModel.Revision.t(),
             telemetry_plan: Cadence.Catalog.MissionModel.RuntimePlan.t(),
             compilation: map(),
             selected_packets: [PacketDefinition.t()],
             unassigned_apids: [non_neg_integer()]
           }}
          | {:error, term()}
  def preview(organization_id, mission_id, %Config{} = config) do
    with {:ok, telemetry} <- fetch_telemetry_for_config(organization_id, mission_id, config) do
      compilation = compile_runtime_artifacts(telemetry, config, 1)

      {:ok,
       %{
         mission_model_revision: telemetry.mission_model_revision,
         telemetry_plan: telemetry.telemetry_plan,
         compilation: compilation,
         selected_packets: selected_packets(telemetry.packet_definitions, config.handled_apids),
         unassigned_apids: unassigned_apids(telemetry.packet_definitions, config.handled_apids)
       }}
    end
  end

  @doc """
  Return advisory visibility for other enabled readers of each APID.

  The result never blocks configuration or activation. Normalized packet
  bindings deliberately have no cross-application uniqueness constraint.
  """
  @spec list_apid_conflicts(binary(), binary(), binary()) ::
          %{non_neg_integer() => String.t()}
  def list_apid_conflicts(organization_id, mission_id, spacecraft_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(spacecraft_id) do
    ApplicationBindingStore.list_apid_conflicts(
      organization_id,
      mission_id,
      spacecraft_id,
      @application_key
    )
  end

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
  @spec compile_mission_contribution(binary(), binary(), [Config.t()]) ::
          {:ok, MissionBindingContribution.t()} | {:error, term()}
  def compile_mission_contribution(organization_id, mission_id, configs)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(configs) do
    {capability_instances, rules, errors} =
      Enum.reduce(configs, {[], [], []}, fn config, {ci_acc, rule_acc, error_acc} ->
        case fetch_telemetry_for_config(organization_id, mission_id, config) do
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

  defp fetch_telemetry_for_config(organization_id, mission_id, %Config{} = config) do
    with {:ok, %Revision{} = revision} <-
           Catalog.fetch_revision(organization_id, mission_id, config.catalog_revision_id) do
      TelemetryProjection.load(organization_id, mission_id, revision)
    end
  end

  defp stamp_applied(configs, %BindingSet{} = binding_set) do
    now = DateTime.utc_now()

    Enum.reduce_while(configs, :ok, fn %Config{} = config, _acc ->
      updated =
        %Config{
          config
          | applied_binding_set_id: binding_set.binding_set_id,
            applied_binding_set_version: binding_set.version,
            applied_at: now
        }

      case updated
           |> config_to_binding()
           |> ApplicationBindingStore.upsert(versioning: :preserve) do
        {:ok, _binding} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp clear_disabled_application_state(organization_id, mission_id) do
    now = DateTime.utc_now()

    from(
      row in BindingRow,
      where:
        row.organization_id == ^organization_id and row.mission_id == ^mission_id and
          row.application_key == ^@application_key and row.enabled == false
    )
    |> Repo.update_all(
      set: [
        applied_binding_set_id: nil,
        applied_binding_set_version: nil,
        applied_at: nil,
        updated_at: now
      ]
    )

    :ok
  end

  defp reconcile_application_state(configs, %BindingSet{} = binding_set) do
    enabled_configs = Enum.filter(configs, & &1.enabled)
    mission_id = binding_set.mission_id
    organization_id = binding_set.organization_id

    case stamp_applied(enabled_configs, binding_set) do
      :ok ->
        clear_disabled_application_state(organization_id, mission_id)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp compile_runtime_artifacts(telemetry, %Config{} = config, binding_set_version) do
    packet_definitions = selected_packets(telemetry.packet_definitions, config.handled_apids)

    capability_instances =
      Enum.map(packet_definitions, fn packet_definition ->
        CapabilityInstance.new(%{
          capability_instance_id:
            capability_instance_id(
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
          binding_rule_id: capability_instance.capability_instance_id <> ":rule",
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

  defp capability_instance_id(revision_id, source_endpoint_id, packet_definition_id) do
    "mission_model_telemetry:#{revision_id}:#{source_endpoint_id}:#{packet_definition_id}"
  end

  defp parse_handled_apids(attrs) do
    attrs
    |> fetch_attr!(:handled_apids)
    |> APIDSelection.parse()
  end

  defp validate_handled_apids(packet_definitions, handled_apids) do
    available_apids = MapSet.new(all_packet_apids(packet_definitions))
    unknown_apids = Enum.reject(handled_apids, &MapSet.member?(available_apids, &1))

    case unknown_apids do
      [] -> :ok
      _unknown_apids -> {:error, {:handled_apids_not_in_revision, Enum.sort(unknown_apids)}}
    end
  end

  defp selected_packets(packet_definitions, handled_apids) do
    allowed_apids = MapSet.new(handled_apids)
    Enum.filter(packet_definitions, &MapSet.member?(allowed_apids, &1.apid))
  end

  defp unassigned_apids(packet_definitions, handled_apids) do
    packet_definitions
    |> all_packet_apids()
    |> Enum.reject(&(&1 in handled_apids))
  end

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

  defp runtime_source_endpoint_id(spacecraft_id), do: "spacecraft_runtime:" <> spacecraft_id

  defp create_managed_runtime_source_endpoint(organization_id, spacecraft) do
    endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: runtime_source_endpoint_id(spacecraft.spacecraft_id),
        mission_id: spacecraft.mission_id,
        spacecraft_id: spacecraft.spacecraft_id,
        scid: spacecraft.scid,
        display_name: spacecraft.display_name,
        metadata: %{"managed_by" => "spacecraft_application_binding"}
      })

    case SourceEndpoints.persist_source_endpoint(organization_id, endpoint) do
      {:ok, persisted} -> {:ok, persisted.source_endpoint_id}
      {:error, reason} -> {:error, reason}
    end
  end

  defp managed_runtime_source_endpoint?(%SourceEndpoint{} = endpoint) do
    endpoint.source_endpoint_id == runtime_source_endpoint_id(endpoint.spacecraft_id) or
      Map.get(endpoint.metadata, "managed_by") in [
        "spacecraft_application_binding",
        "telemetry_decom"
      ]
  end

  defp fetch_required(attrs, key) do
    case Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key)) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _missing -> {:error, {:missing_attr, key}}
    end
  end
end
