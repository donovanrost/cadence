defmodule Cadence.Applications.TelemetryDecom do
  @moduledoc """
  Spacecraft-centered configuration for the built-in Telemetry Decom
  application.

  Users think in terms of spacecraft and catalog revisions.
  This module resolves those choices into the existing runtime path:

    spacecraft → catalog revision → telemetry snapshot
    → compiled binding set rules → persisted + activated mission binding set

  The mission binding set id `"telemetry_decom:<mission_id>"` is shared across
  all spacecraft in a mission. Internally each spacecraft config is resolved to
  a managed runtime source endpoint so the dispatcher can disambiguate
  overlapping APIDs across heterogeneous spacecraft.
  """

  import Ecto.Query

  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Applications.TelemetryDecom.APIDSelection
  alias Cadence.Applications.TelemetryDecom.Config
  alias Cadence.Catalog
  alias Cadence.Catalog.Revision
  alias Cadence.Catalog.Telemetry.Compiler.Result, as: CompilerResult
  alias Cadence.Catalog.Telemetry.Packet
  alias Cadence.Catalog.Telemetry.RuntimeArtifacts
  alias Cadence.Catalog.Telemetry.Snapshot, as: TelemetryCatalogSnapshot
  alias Cadence.Governance
  alias Cadence.Missions
  alias Cadence.Persistence.Schemas.SpacecraftTelemetryDecomConfigRow
  alias Cadence.Repo
  alias Cadence.Runtime
  alias Cadence.SourceEndpoints
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.SpacecraftStore

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
         :ok <- ensure_telemetry_revision(revision),
         {:ok, snapshot} <-
           Catalog.fetch_telemetry_snapshot(
             organization_id,
             mission_id,
             revision.telemetry_snapshot_id
           ),
         {:ok, handled_apids} <- parse_handled_apids(attrs),
         :ok <- validate_handled_apids(snapshot, handled_apids),
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
      Repo.get_by(SpacecraftTelemetryDecomConfigRow,
        organization_id: organization_id,
        mission_id: mission_id,
        spacecraft_id: spacecraft_id
      )

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
        catalog_revision_id: catalog_revision_id,
        handled_apids: handled_apids,
        source_endpoint_id: source_endpoint_id,
        enabled: enabled,
        applied_binding_set_id: preserved_stamp.applied_binding_set_id,
        applied_binding_set_version: preserved_stamp.applied_binding_set_version,
        applied_at: preserved_stamp.applied_at,
        metadata: Map.get(attrs, :metadata, %{})
      })

    changeset = SpacecraftTelemetryDecomConfigRow.changeset(config)

    upsert_opts = [
      on_conflict:
        {:replace,
         [
           :catalog_revision_id,
           :handled_apids,
           :source_endpoint_id,
           :enabled,
           :metadata,
           :applied_binding_set_id,
           :applied_binding_set_version,
           :applied_at,
           :updated_at
         ]},
      conflict_target: [:spacecraft_id]
    ]

    case Repo.insert(changeset, upsert_opts) do
      {:ok, row} -> {:ok, SpacecraftTelemetryDecomConfigRow.to_domain(row)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp preserved_applied_stamp(
         %SpacecraftTelemetryDecomConfigRow{
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

  defp resolve_enabled(attrs, %SpacecraftTelemetryDecomConfigRow{} = existing) do
    Map.get(attrs, :enabled, Map.get(attrs, "enabled", existing.enabled))
  end

  defp resolve_enabled(attrs, nil) do
    Map.get(attrs, :enabled, Map.get(attrs, "enabled", true))
  end

  @spec fetch_config(binary(), binary(), binary()) ::
          {:ok, Config.t()} | {:error, :not_configured}
  def fetch_config(organization_id, mission_id, spacecraft_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(spacecraft_id) do
    case Repo.get_by(SpacecraftTelemetryDecomConfigRow,
           organization_id: organization_id,
           mission_id: mission_id,
           spacecraft_id: spacecraft_id
         ) do
      nil -> {:error, :not_configured}
      row -> {:ok, SpacecraftTelemetryDecomConfigRow.to_domain(row)}
    end
  end

  @spec list_configs(binary(), binary()) :: [Config.t()]
  def list_configs(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    SpacecraftTelemetryDecomConfigRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id
    )
    |> order_by([row], asc: row.spacecraft_id)
    |> Repo.all()
    |> Enum.map(&SpacecraftTelemetryDecomConfigRow.to_domain/1)
  end

  @doc """
  Compile every enabled spacecraft config in the mission into a single merged
  binding set and activate it. Returns the updated config for the spacecraft
  that triggered the apply.
  """
  @spec apply_mission(binary(), binary(), binary()) ::
          {:ok, Config.t()} | {:error, term()}
  def apply_mission(organization_id, mission_id, triggering_spacecraft_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(triggering_spacecraft_id) do
    with {:ok, _mission} <- Missions.fetch_mission(organization_id, mission_id),
         {:ok, config} <-
           fetch_config(organization_id, mission_id, triggering_spacecraft_id),
         all_configs <- list_configs(organization_id, mission_id),
         configs <- Enum.filter(all_configs, & &1.enabled),
         {:ok, binding_set} <-
           compile_mission_binding_set(organization_id, mission_id, configs),
         {:ok, _persisted} <- Governance.persist_binding_set(organization_id, binding_set),
         {:ok, _activation} <-
           Runtime.activate_binding_set(
             mission_id,
             binding_set.binding_set_id,
             binding_set.version,
             metadata: %{"application" => "telemetry_decom"}
           ),
         :ok <- reconcile_application_state(all_configs, binding_set) do
      fetch_config(organization_id, mission_id, triggering_spacecraft_id)
      |> case do
        {:ok, config} -> {:ok, config}
        {:error, _} -> {:ok, config}
      end
    end
  end

  @doc """
  Disable a spacecraft's Telemetry Decom configuration. The configuration is
  kept so the user can re-enable without re-entering choices, but it will no
  longer contribute rules on the next apply.
  """
  @spec disable(binary(), binary(), binary()) :: {:ok, Config.t()} | {:error, term()}
  def disable(organization_id, mission_id, spacecraft_id) do
    with {:ok, %Config{} = config} <- fetch_config(organization_id, mission_id, spacecraft_id) do
      changeset =
        SpacecraftTelemetryDecomConfigRow.changeset(%Config{config | enabled: false})

      case Repo.insert(changeset,
             on_conflict: {:replace, [:enabled, :updated_at]},
             conflict_target: [:spacecraft_id]
           ) do
        {:ok, row} -> {:ok, SpacecraftTelemetryDecomConfigRow.to_domain(row)}
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
    do: "telemetry_decom:" <> mission_id

  @doc """
  Compile the preview runtime artifacts for a single config. Exposed for the
  UI so it can show packet definition counts and diagnostics without applying.
  """
  @spec preview(binary(), binary(), Config.t()) ::
          {:ok,
           %{
             snapshot: TelemetryCatalogSnapshot.t(),
             compilation: RuntimeArtifacts.t(),
             selected_packets: [Packet.t()],
             unassigned_apids: [non_neg_integer()]
           }}
          | {:error, term()}
  def preview(organization_id, mission_id, %Config{} = config) do
    with {:ok, snapshot} <- fetch_snapshot_for_config(organization_id, mission_id, config) do
      compilation = compile_runtime_artifacts(snapshot, config, 1)

      {:ok,
       %{
         snapshot: snapshot,
         compilation: compilation,
         selected_packets: selected_packets(snapshot, config.handled_apids),
         unassigned_apids: unassigned_apids(snapshot, config.handled_apids)
       }}
    end
  end

  @doc """
  Return a map of `apid => other_application_display_name` for every APID
  already claimed by a *different* enabled application on this spacecraft.

  Today Telemetry Decom is the only built-in application, so this always
  returns an empty map. The function exists so the UI can render a conflict
  column without future wiring when additional applications land.
  """
  @spec list_apid_conflicts(binary(), binary(), binary()) ::
          %{non_neg_integer() => String.t()}
  def list_apid_conflicts(organization_id, mission_id, spacecraft_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(spacecraft_id) do
    %{}
  end

  @type apid_row :: %{
          apid: non_neg_integer(),
          packets: [Packet.t()],
          def_count: non_neg_integer(),
          rate_hz: number() | nil,
          short_description: String.t() | nil
        }

  @type apid_row_result :: %{
          rows: [apid_row()],
          points_by_id: %{optional(binary()) => Cadence.Catalog.Telemetry.Point.t()}
        }

  @doc """
  Return one row per APID present in the revision's telemetry snapshot.

  Each row carries every packet definition that shares the APID, along with
  a primary rate (from the first packet's `expected_rate_hz`) and a short
  description derived from the first packet's `short_description` or a
  truncated `description`. Rows are sorted by APID ascending.

  Also returns a `points_by_id` map keyed by `point_id` for looking up
  human-readable point names in the UI.
  """
  @spec list_revision_apid_rows(binary(), binary(), binary()) ::
          {:ok, apid_row_result()} | {:error, term()}
  def list_revision_apid_rows(organization_id, mission_id, catalog_revision_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(catalog_revision_id) do
    with {:ok, %Revision{} = revision} <-
           Catalog.fetch_revision(organization_id, mission_id, catalog_revision_id),
         :ok <- ensure_telemetry_revision(revision),
         {:ok, snapshot} <-
           Catalog.fetch_telemetry_snapshot(
             organization_id,
             mission_id,
             revision.telemetry_snapshot_id
           ) do
      rows =
        snapshot.packets
        |> Enum.filter(&is_integer(&1.apid))
        |> Enum.group_by(& &1.apid)
        |> Enum.sort_by(fn {apid, _} -> apid end)
        |> Enum.map(fn {apid, packets} ->
          %{
            apid: apid,
            packets: packets,
            def_count: length(packets),
            rate_hz: rate_of(packets),
            short_description: short_description_of(List.first(packets))
          }
        end)

      points_by_id = Map.new(snapshot.points, &{&1.point_id, &1})

      {:ok, %{rows: rows, points_by_id: points_by_id}}
    end
  end

  defp rate_of([%Packet{expected_rate_hz: hz} | _]), do: hz
  defp rate_of([]), do: nil

  defp short_description_of(nil), do: nil
  defp short_description_of(%Packet{short_description: desc}) when is_binary(desc), do: desc

  defp short_description_of(%Packet{description: desc}) when is_binary(desc) do
    if String.length(desc) <= 160, do: desc, else: String.slice(desc, 0, 157) <> "…"
  end

  defp short_description_of(_), do: nil

  defp compile_mission_binding_set(organization_id, mission_id, []) do
    next_version = next_binding_set_version(organization_id, mission_id)

    {:ok,
     BindingSet.new(%{
       binding_set_id: binding_set_id(mission_id),
       organization_id: organization_id,
       mission_id: mission_id,
       version: next_version,
       capability_instances: [],
       rules: []
     })}
  end

  defp compile_mission_binding_set(organization_id, mission_id, configs) do
    next_version = next_binding_set_version(organization_id, mission_id)

    {capability_instances, rules, errors} =
      Enum.reduce(configs, {[], [], []}, fn config, {ci_acc, rule_acc, error_acc} ->
        case fetch_snapshot_for_config(organization_id, mission_id, config) do
          {:ok, snapshot} ->
            compilation = compile_runtime_artifacts(snapshot, config, next_version)

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
         BindingSet.new(%{
           binding_set_id: binding_set_id(mission_id),
           organization_id: organization_id,
           mission_id: mission_id,
           version: next_version,
           capability_instances: capability_instances,
           rules: rules
         })}

      errors ->
        {:error, {:config_compile_failed, errors}}
    end
  end

  defp fetch_snapshot_for_config(organization_id, mission_id, %Config{} = config) do
    with {:ok, %Revision{telemetry_snapshot_id: snapshot_id} = revision} <-
           Catalog.fetch_revision(organization_id, mission_id, config.catalog_revision_id),
         :ok <- ensure_telemetry_revision(revision) do
      Catalog.fetch_telemetry_snapshot(organization_id, mission_id, snapshot_id)
    end
  end

  defp next_binding_set_version(organization_id, mission_id) do
    case Governance.fetch_latest_binding_set(
           organization_id,
           mission_id,
           binding_set_id(mission_id)
         ) do
      {:ok, %{version: version}} -> version + 1
      {:error, :binding_set_not_found} -> 1
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

      case Repo.insert(SpacecraftTelemetryDecomConfigRow.changeset(updated),
             on_conflict:
               {:replace,
                [
                  :applied_binding_set_id,
                  :applied_binding_set_version,
                  :applied_at,
                  :updated_at
                ]},
             conflict_target: [:spacecraft_id]
           ) do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp clear_disabled_application_state(organization_id, mission_id) do
    now = DateTime.utc_now()

    from(
      row in SpacecraftTelemetryDecomConfigRow,
      where:
        row.organization_id == ^organization_id and row.mission_id == ^mission_id and
          row.enabled == false
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

  defp compile_runtime_artifacts(snapshot, %Config{} = config, binding_set_version) do
    compilation =
      RuntimeArtifacts.compile(
        snapshot,
        binding_set_version: binding_set_version,
        target_scope: :source_endpoint,
        source_endpoint_ref: config.source_endpoint_id
      )

    filter_runtime_artifacts(compilation, config.handled_apids, binding_set_version)
  end

  defp filter_runtime_artifacts(compilation, handled_apids, binding_set_version) do
    allowed_apids = MapSet.new(handled_apids)

    packet_definitions =
      Enum.filter(compilation.compiler_result.packet_definitions, fn packet_definition ->
        MapSet.member?(allowed_apids, packet_definition.apid)
      end)

    allowed_definition_ids =
      MapSet.new(packet_definitions, & &1.packet_definition_id)

    selected_packet_ids =
      compilation.snapshot
      |> selected_packets(handled_apids)
      |> MapSet.new(& &1.packet_id)

    selector_inputs =
      Enum.filter(compilation.compiler_result.selector_inputs, fn selector_input ->
        MapSet.member?(allowed_definition_ids, selector_input.packet_definition_id) and
          MapSet.member?(selected_packet_ids, selector_input.packet_id)
      end)

    diagnostics =
      Enum.filter(compilation.compiler_result.diagnostics, fn diagnostic ->
        case Map.get(diagnostic.metadata, "packet_id") do
          nil -> true
          packet_id -> MapSet.member?(selected_packet_ids, packet_id)
        end
      end)

    compiler_result =
      CompilerResult.new(%{
        packet_definitions: packet_definitions,
        selector_inputs: selector_inputs,
        diagnostics: diagnostics
      })

    %{
      compilation
      | compiler_result: compiler_result,
        binding_set:
          RuntimeArtifacts.build_binding_set(
            compilation.snapshot,
            compiler_result,
            binding_set_version: binding_set_version
          )
    }
  end

  defp parse_handled_apids(attrs) do
    attrs
    |> fetch_attr!(:handled_apids)
    |> APIDSelection.parse()
  end

  defp validate_handled_apids(%TelemetryCatalogSnapshot{} = snapshot, handled_apids) do
    available_apids = MapSet.new(all_snapshot_apids(snapshot))
    unknown_apids = Enum.reject(handled_apids, &MapSet.member?(available_apids, &1))

    case unknown_apids do
      [] -> :ok
      _unknown_apids -> {:error, {:handled_apids_not_in_revision, Enum.sort(unknown_apids)}}
    end
  end

  defp selected_packets(%TelemetryCatalogSnapshot{} = snapshot, handled_apids) do
    allowed_apids = MapSet.new(handled_apids)
    Enum.filter(snapshot.packets, &MapSet.member?(allowed_apids, &1.apid))
  end

  defp unassigned_apids(%TelemetryCatalogSnapshot{} = snapshot, handled_apids) do
    snapshot
    |> all_snapshot_apids()
    |> Enum.reject(&(&1 in handled_apids))
  end

  defp all_snapshot_apids(%TelemetryCatalogSnapshot{} = snapshot) do
    snapshot.packets
    |> Enum.map(& &1.apid)
    |> Enum.filter(&is_integer/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp ensure_telemetry_revision(%Revision{telemetry_snapshot_id: nil}),
    do: {:error, :catalog_revision_missing_telemetry}

  defp ensure_telemetry_revision(%Revision{}), do: :ok

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
        metadata: %{"managed_by" => "telemetry_decom"}
      })

    case SourceEndpoints.persist_source_endpoint(organization_id, endpoint) do
      {:ok, persisted} -> {:ok, persisted.source_endpoint_id}
      {:error, reason} -> {:error, reason}
    end
  end

  defp managed_runtime_source_endpoint?(%SourceEndpoint{} = endpoint) do
    endpoint.source_endpoint_id == runtime_source_endpoint_id(endpoint.spacecraft_id) or
      Map.get(endpoint.metadata, "managed_by") == "telemetry_decom"
  end

  defp fetch_required(attrs, key) do
    case Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key)) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _missing -> {:error, {:missing_attr, key}}
    end
  end
end
