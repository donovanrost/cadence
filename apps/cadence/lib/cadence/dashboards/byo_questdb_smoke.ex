defmodule Cadence.Dashboards.BYOQuestDBSmoke do
  @moduledoc """
  End-to-end smoke check for a customer-owned QuestDB dashboard source.

  This smoke is intentionally above the storage adapter smoke. It proves that a
  customer-owned dashboard data source can resolve runtime credential material,
  probe the external QuestDB endpoint, and execute a dashboard telemetry history
  read against that same endpoint without persisting secret material.
  """

  alias Cadence.Dashboards.{
    DataBinding,
    DataSource,
    DataSources,
    PlannedSourceRequest,
    SourceCredentialMaterial,
    SourceCredentials,
    SourceRegistry
  }

  alias Cadence.Dashboards.SourceCredentials.EnvMaterialResolver
  alias Cadence.Missions.Mission
  alias Cadence.Organizations.Organization
  alias Cadence.Repo
  alias Cadence.Telemetry.Sample

  alias Cadence.Telemetry.Storage.{
    ObservationEnvelope,
    QuestDB.ObservationReader,
    QuestDB.ObservationWriter,
    QuestDB.SchemaMigrator,
    WriteContext
  }

  @default_organization_id "questdb-byo-smoke-org"
  @default_mission_id "questdb-byo-smoke-mission"
  @default_data_source_id "customer_byo_questdb_smoke"
  @default_binding_id "customer_byo_questdb_smoke_flight"
  @default_credentials_ref "secret://questdb-byo-smoke/dashboard/customer-questdb"
  @default_material_profile "cadence-byo-questdb-smoke"
  @default_http_endpoint_env "CADENCE_BYO_QUESTDB_HTTP_ENDPOINT"
  @default_http_endpoint "http://127.0.0.1:9100"
  @default_point_id "SMOKE.byo_counter"

  @type result :: %{
          sample_id: binary(),
          organization_id: binary(),
          mission_id: binary(),
          data_source_id: binary(),
          binding_id: binary(),
          point_id: binary(),
          value: integer(),
          http_endpoint: binary(),
          source_health: atom(),
          returned_frame_count: non_neg_integer(),
          run_id: binary(),
          cleanup?: boolean(),
          applied_migrations: [SchemaMigrator.migration()]
        }

  @spec run(keyword()) :: {:ok, result()} | {:error, term()}
  def run(opts \\ []) when is_list(opts) do
    with :ok <- maybe_start_cadence(opts),
         {:ok, smoke_context} <- build_context(opts) do
      smoke_context
      |> run_smoke(opts)
      |> maybe_cleanup_smoke(smoke_context, opts)
    end
  end

  defp run_smoke(smoke_context, opts) do
    with {:ok, credential_material} <- ensure_source_contract(smoke_context, opts),
         storage_opts <- storage_opts(credential_material, opts),
         {:ok, applied_migrations} <- SchemaMigrator.apply_pending(storage_opts),
         {:ok, sample} <- write_sample(smoke_context, storage_opts, opts),
         {:ok, source_health} <- probe_source(smoke_context, opts),
         {:ok, frame_count} <- resolve_dashboard_history(smoke_context, sample, opts) do
      {:ok,
       %{
         run_id: smoke_context.run_id,
         sample_id: sample.sample_id,
         organization_id: smoke_context.organization_id,
         mission_id: smoke_context.mission_id,
         data_source_id: smoke_context.data_source_id,
         binding_id: smoke_context.binding_id,
         point_id: sample.point_id,
         value: sample.engineering_value,
         http_endpoint: Keyword.fetch!(storage_opts, :http_endpoint),
         source_health: source_health,
         returned_frame_count: frame_count,
         cleanup?: cleanup?(opts),
         applied_migrations: applied_migrations
       }}
    end
  end

  defp maybe_start_cadence(opts) do
    if Keyword.get(opts, :start_cadence?, true) do
      case Application.ensure_all_started(:cadence) do
        {:ok, _started} -> :ok
        {:error, reason} -> {:error, {:cadence_start_failed, reason}}
      end
    else
      :ok
    end
  end

  defp build_context(opts) do
    timestamp = Keyword.get(opts, :timestamp, DateTime.utc_now())
    run_id = Keyword.get(opts, :run_id, "run-#{System.unique_integer([:positive])}")
    generated_organization? = not Keyword.has_key?(opts, :organization_id)
    generated_mission? = not Keyword.has_key?(opts, :mission_id)

    {:ok,
     %{
       run_id: run_id,
       generated_organization?: generated_organization?,
       generated_mission?: generated_mission?,
       organization_id:
         Keyword.get(opts, :organization_id, "#{@default_organization_id}-#{run_id}"),
       mission_id: Keyword.get(opts, :mission_id, "#{@default_mission_id}-#{run_id}"),
       data_source_id: Keyword.get(opts, :data_source_id, "#{@default_data_source_id}_#{run_id}"),
       binding_id: Keyword.get(opts, :binding_id, "#{@default_binding_id}_#{run_id}"),
       credentials_ref:
         Keyword.get(
           opts,
           :credentials_ref,
           "#{@default_credentials_ref}/#{run_id}"
         ),
       material_profile: Keyword.get(opts, :material_profile, @default_material_profile),
       endpoint_ref: Keyword.get(opts, :endpoint_ref, "endpoint://customer/questdb-smoke"),
       point_id: Keyword.get(opts, :point_id, @default_point_id),
       spacecraft_id: Keyword.get(opts, :spacecraft_id, "smoke-spacecraft"),
       sample_id:
         Keyword.get(opts, :sample_id, "sample-byo-questdb-#{System.unique_integer([:positive])}"),
       value: Keyword.get(opts, :value, System.unique_integer([:positive])),
       timestamp: timestamp
     }}
  end

  defp ensure_source_contract(context, opts) do
    with {:ok, _organization} <- ensure_organization(context),
         {:ok, _mission} <- ensure_mission(context),
         {:ok, _reference} <- ensure_credential_reference(context, opts),
         {:ok, data_source} <- ensure_data_source(context, opts),
         {:ok, _binding} <- ensure_data_binding(context) do
      resolve_material(context, data_source, opts)
    end
  end

  defp maybe_cleanup_smoke({:ok, result}, context, opts) do
    if cleanup?(opts) do
      case cleanup(context) do
        :ok -> {:ok, result}
        {:error, reason} -> {:error, {:cleanup_failed, reason, result}}
      end
    else
      {:ok, result}
    end
  end

  defp maybe_cleanup_smoke({:error, reason}, context, opts) do
    if cleanup?(opts) do
      _cleanup_result = cleanup(context)
    end

    {:error, reason}
  end

  defp cleanup?(opts), do: Keyword.get(opts, :cleanup?, false)

  defp cleanup(context) do
    Enum.reduce_while(cleanup_queries(context), :ok, fn {sql, params}, :ok ->
      case Repo.query(sql, params) do
        {:ok, _result} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp cleanup_queries(context) do
    [
      operational_events_cleanup_query(context),
      {"DELETE FROM dashboard_source_health_statuses WHERE data_source_id = $1 OR source_health_event_id IN (SELECT source_health_event_id FROM dashboard_source_health_events WHERE data_source_id = $1)",
       [context.data_source_id]},
      {"DELETE FROM dashboard_source_health_events WHERE data_source_id = $1",
       [context.data_source_id]},
      {"DELETE FROM dashboard_data_binding_events WHERE binding_id = $1", [context.binding_id]},
      {"DELETE FROM dashboard_data_bindings WHERE binding_id = $1", [context.binding_id]},
      {"DELETE FROM dashboard_data_source_events WHERE data_source_id = $1",
       [context.data_source_id]},
      {"DELETE FROM dashboard_data_sources WHERE data_source_id = $1", [context.data_source_id]},
      {"DELETE FROM dashboard_source_credential_events WHERE credentials_ref = $1",
       [context.credentials_ref]},
      {"DELETE FROM dashboard_source_credential_references WHERE credentials_ref = $1",
       [context.credentials_ref]}
    ] ++ cleanup_scope_queries(context)
  end

  defp cleanup_scope_queries(context) do
    mission_queries =
      if context.generated_mission? do
        [
          {"DELETE FROM missions WHERE mission_id = $1 AND organization_id = $2",
           [context.mission_id, context.organization_id]}
        ]
      else
        []
      end

    organization_queries =
      if context.generated_organization? and context.generated_mission? do
        [
          {"DELETE FROM organizations WHERE organization_id = $1", [context.organization_id]}
        ]
      else
        []
      end

    mission_queries ++ organization_queries
  end

  defp operational_events_cleanup_query(context) do
    {"""
     DELETE FROM operational_events
     WHERE subject_id IN ($1, $2, $3)
        OR source_record_id IN (
          SELECT data_source_event_id
          FROM dashboard_data_source_events
          WHERE data_source_id = $1
        )
        OR source_record_id IN (
          SELECT data_binding_event_id
          FROM dashboard_data_binding_events
          WHERE binding_id = $2
        )
        OR source_record_id IN (
          SELECT source_health_event_id
          FROM dashboard_source_health_events
          WHERE data_source_id = $1
        )
        OR source_record_id IN (
          SELECT source_credential_event_id
          FROM dashboard_source_credential_events
          WHERE credentials_ref = $3
        )
     """, [context.data_source_id, context.binding_id, context.credentials_ref]}
  end

  defp ensure_organization(context) do
    Cadence.persist_organization(%Organization{
      organization_id: context.organization_id,
      slug: context.organization_id,
      display_name: "QuestDB BYO smoke organization"
    })
  end

  defp ensure_mission(context) do
    Cadence.persist_mission(%Mission{
      mission_id: context.mission_id,
      organization_id: context.organization_id,
      slug: context.mission_id,
      display_name: "QuestDB BYO smoke mission"
    })
  end

  defp ensure_credential_reference(context, opts) do
    case SourceCredentials.fetch_reference(context.credentials_ref) do
      {:ok, reference} ->
        {:ok, reference}

      {:error, :credential_reference_not_found} ->
        attrs = %{
          credentials_ref: context.credentials_ref,
          organization_id: context.organization_id,
          mission_id: context.mission_id,
          data_source_id: context.data_source_id,
          owner: :customer,
          kind: :byo_tsdb_connection,
          provider: "questdb",
          metadata: %{
            endpoint_ref: context.endpoint_ref,
            material_env_profile: context.material_profile
          }
        }

        case SourceCredentials.register_reference(attrs, actor_id: Keyword.get(opts, :actor_id)) do
          {:ok, reference, _event} -> {:ok, reference}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp ensure_data_source(context, _opts) do
    DataSources.persist_data_source(%DataSource{
      data_source_id: context.data_source_id,
      owner: :customer,
      kind: :byo_tsdb,
      adapter: Cadence.Dashboards.Sources.Telemetry,
      organization_id: context.organization_id,
      mission_id: context.mission_id,
      isolation_level: :customer_owned,
      credentials_ref: context.credentials_ref,
      capabilities: %{range_scan?: true, watermarks?: true},
      metadata: %{storage: :questdb, endpoint_ref: context.endpoint_ref}
    })
  end

  defp ensure_data_binding(context) do
    DataSources.persist_data_binding(%DataBinding{
      binding_id: context.binding_id,
      organization_id: context.organization_id,
      mission_id: context.mission_id,
      realm: :flight,
      logical_source: :telemetry,
      data_source_id: context.data_source_id,
      dataset: "customer-byo-smoke",
      priority: 0
    })
  end

  defp resolve_material(context, %DataSource{} = _data_source, opts) do
    SourceCredentials.resolve_material(
      context.credentials_ref,
      source_material_opts(context, opts)
    )
  end

  defp write_sample(context, storage_opts, _opts) do
    with {:ok, write_context} <-
           WriteContext.new(
             organization_id: context.organization_id,
             mission_id: context.mission_id,
             realm: :flight,
             data_source_id: context.data_source_id,
             binding_id: context.binding_id,
             source_endpoint_id: "questdb-byo-smoke",
             recorded_at: context.timestamp,
             metadata: %{source: :byo_questdb_smoke}
           ),
         sample <- sample(context),
         {:ok, envelope} <- ObservationEnvelope.from_sample(write_context, sample),
         :ok <- ObservationWriter.persist_envelopes([envelope], storage_opts) do
      {:ok, sample}
    end
  end

  defp sample(context) do
    %Sample{
      sample_id: context.sample_id,
      mission_id: context.mission_id,
      spacecraft_id: context.spacecraft_id,
      point_id: context.point_id,
      point_name: context.point_id,
      packet_definition_id: "byo-smoke-packet-def",
      packet_definition_version: 1,
      packet_id: "packet-#{context.sample_id}",
      evidence_id: "evidence-#{context.sample_id}",
      raw_value: context.value,
      engineering_value: context.value,
      quality_state: :good,
      generation_time: context.timestamp,
      receipt_time: context.timestamp,
      provenance: %{source: :byo_questdb_smoke}
    }
  end

  defp probe_source(context, opts) do
    probe_opts =
      source_material_opts(context, opts) ++
        [
          actor_id: Keyword.get(opts, :actor_id, "questdb-byo-smoke"),
          questdb_probe?: true,
          invalidate_runtime_cache?: false
        ] ++ maybe_questdb_exec_fun(opts)

    case DataSources.probe_data_source(
           context.data_source_id,
           %{observed_at: context.timestamp},
           probe_opts
         ) do
      {:ok, event, _status} when event.source_health == :healthy ->
        {:ok, event.source_health}

      {:ok, event, _status} ->
        {:error, {:source_probe_not_healthy, event.source_health, event.payload}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp resolve_dashboard_history(context, sample, opts) do
    resolve_dashboard_history_attempt(
      context,
      sample,
      opts,
      history_read_attempts(opts)
    )
  end

  defp resolve_dashboard_history_attempt(context, sample, opts, attempts_remaining) do
    case do_resolve_dashboard_history(context, sample, opts) do
      {:error, {:sample_not_read_back_through_dashboard, _sample_id, _frame}}
      when attempts_remaining > 1 ->
        sleep(history_retry_sleep_ms(opts))
        resolve_dashboard_history_attempt(context, sample, opts, attempts_remaining - 1)

      result ->
        result
    end
  end

  defp do_resolve_dashboard_history(context, sample, opts) do
    request = source_request(context, sample)

    resolve_opts =
      source_material_opts(context, opts) ++
        [
          persisted?: true,
          source_opts: %{telemetry: [history_fun: questdb_history_fun(opts)]}
        ]

    request
    |> SourceRegistry.resolve(resolve_opts)
    |> assert_history_frame(sample)
  end

  defp history_read_attempts(opts) do
    opts
    |> Keyword.get(:history_read_attempts, 5)
    |> max(1)
  end

  defp history_retry_sleep_ms(opts) do
    opts
    |> Keyword.get(:history_retry_sleep_ms, 100)
    |> max(0)
  end

  defp sleep(0), do: :ok
  defp sleep(ms), do: Process.sleep(ms)

  defp questdb_history_fun(opts) do
    exec_opts = exec_opts(opts)

    fn organization_id, mission_id, point_id, read_opts ->
      read_opts =
        read_opts
        |> Keyword.put_new(:organization_id, organization_id)
        |> Keyword.merge(exec_opts)

      ObservationReader.sample_history_result(mission_id, point_id, read_opts)
    end
  end

  defp source_request(context, sample) do
    PlannedSourceRequest.new(%{
      request_id: "byo-questdb-smoke-history",
      organization_id: context.organization_id,
      mission_id: context.mission_id,
      logical_source: :telemetry,
      observables: [sample.point_id],
      scope_context: %{primary: %{kind: "spacecraft", mode: "one", ids: [sample.spacecraft_id]}},
      time_context: %{
        axis: :receipt_time,
        from: sample.receipt_time,
        to: sample.receipt_time
      },
      data_context: %{realm: :flight},
      sampling: %{mode: :raw_series},
      value_type: :engineering
    })
  end

  defp assert_history_frame(result, sample) do
    cond do
      result.meta.degraded? ->
        {:error, {:dashboard_resolution_degraded, result.warnings}}

      result.frames == [] ->
        {:error, :dashboard_resolution_returned_no_frames}

      frame_contains_sample?(List.first(result.frames), sample) ->
        {:ok, length(result.frames)}

      true ->
        {:error,
         {:sample_not_read_back_through_dashboard, sample.sample_id, List.first(result.frames)}}
    end
  end

  defp frame_contains_sample?(frame, sample) do
    frame.fields
    |> Enum.find(&(&1.name == sample.point_id))
    |> case do
      nil -> false
      field -> sample.engineering_value in field.values
    end
  end

  defp source_material_opts(context, opts) do
    endpoint_env = Keyword.get(opts, :http_endpoint_env, @default_http_endpoint_env)

    [
      organization_id: context.organization_id,
      mission_id: context.mission_id,
      data_source_id: context.data_source_id,
      credential_material_resolver: {EnvMaterialResolver, :resolve},
      env_material_profiles: %{
        context.material_profile => %{http_endpoint_env: endpoint_env}
      },
      env_reader: env_reader(endpoint_env, opts)
    ]
  end

  defp env_reader(endpoint_env, opts) do
    endpoint = Keyword.get(opts, :http_endpoint)
    configured_reader = Keyword.get(opts, :env_reader)

    cond do
      is_binary(endpoint) and endpoint != "" ->
        fn
          ^endpoint_env -> endpoint
          name when is_function(configured_reader, 1) -> configured_reader.(name)
          name -> System.get_env(name)
        end

      is_function(configured_reader, 1) ->
        configured_reader

      true ->
        fn
          ^endpoint_env ->
            System.get_env(endpoint_env) || @default_http_endpoint

          name ->
            System.get_env(name)
        end
    end
  end

  defp storage_opts(%SourceCredentialMaterial{} = credential_material, opts) do
    credential_material
    |> SourceCredentialMaterial.adapter_options()
    |> put_storage_auth_headers()
    |> Keyword.merge(exec_opts(opts))
  end

  defp put_storage_auth_headers(material_opts) do
    material_opts
    |> Keyword.put(:headers, connection_headers(material_opts))
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == [] or value == "" end)
  end

  defp connection_headers(material) do
    headers = material |> Keyword.get(:headers, []) |> normalize_headers()

    cond do
      bearer_token = Keyword.get(material, :bearer_token) ->
        [{"authorization", "Bearer #{bearer_token}"} | headers]

      username = Keyword.get(material, :username) ->
        case Keyword.get(material, :password) do
          password when is_binary(password) ->
            [{"authorization", "Basic #{Base.encode64("#{username}:#{password}")}"} | headers]

          _other ->
            headers
        end

      true ->
        headers
    end
  end

  defp normalize_headers(headers) when is_list(headers) do
    Enum.flat_map(headers, fn
      {key, value} -> [{to_string(key), to_string(value)}]
      _other -> []
    end)
  end

  defp normalize_headers(_headers), do: []

  defp exec_opts(opts) do
    opts
    |> Keyword.take([:exec_fun, :timeout])
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp maybe_questdb_exec_fun(opts) do
    case Keyword.get(opts, :questdb_exec_fun, Keyword.get(opts, :exec_fun)) do
      nil -> []
      exec_fun -> [questdb_exec_fun: exec_fun]
    end
  end
end
