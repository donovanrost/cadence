defmodule Cadence.Dashboards.Sources.Telemetry do
  @moduledoc """
  Dashboard telemetry source adapter.

  This first adapter slice supports latest telemetry values and bounded raw
  telemetry history over receipt time. It intentionally does not make the
  planner execute IO; callers pass a `PlannedSourceRequest` here after planning.
  """

  alias Cadence.Dashboards.{
    DataContext,
    DataLinks,
    DataSource,
    Field,
    Frame,
    PlannedSourceRequest,
    ResolveWarning,
    RuntimeCacheKey,
    ScopeContext,
    SourceActions,
    SourceCapabilities,
    SourceFacts,
    SourceProbe,
    SourceResult,
    SourceWatermark,
    TelemetryActions,
    TelemetryRevisionSummary
  }

  alias Cadence.Telemetry.{Sample, SelectionPolicy}
  alias Cadence.Telemetry.Storage, as: TelemetryStorage
  alias Cadence.Telemetry.Storage.QuestDB.{ObservationReader, ObservationRow, RestClient}

  @history_sampling_modes [:raw_series, :bounded_history, :bounded_raw_series]
  @native_decimated_sampling_modes [:decimated_envelope]
  @supported_sampling_modes [:latest | @history_sampling_modes]
  @active_backfill_lifecycle_event_types [
    :backfill_requested,
    :backfill_approved,
    :backfill_started,
    :backfill_failed,
    :backfill_retried,
    :import_requested,
    :import_approved,
    :import_started,
    :import_failed,
    :import_retried
  ]
  @terminal_backfill_lifecycle_event_types [
    :backfill_rejected,
    :backfill_completed,
    :import_rejected,
    :import_completed,
    :late_data_accepted,
    :late_data_rejected
  ]
  @default_limit 10_000
  @type decimated_history_fun :: (binary() | nil, binary(), binary(), keyword() ->
                                    [map()] | {:ok, map()} | map() | {:error, term()})
  @type history_fun :: (binary() | nil, binary(), binary(), keyword() ->
                          [Sample.t()] | {:ok, map()} | map() | {:error, term()})
  @type latest_fun :: (binary() | nil, binary(), binary(), keyword() -> Sample.t() | nil)
  @type watermark_fun :: (binary() | nil, binary(), binary(), keyword() ->
                            {:ok, map()} | {:error, term()} | map())

  @spec capabilities() :: SourceCapabilities.t()
  def capabilities do
    SourceCapabilities.new(%{
      logical_source: :telemetry,
      supported_sampling: @supported_sampling_modes,
      supported_products: [
        :latest_value,
        :bounded_receipt_time_history,
        :bounded_generation_time_history
      ],
      supported_time_axes: [:generation_time, :receipt_time],
      supported_value_types: [:raw, :engineering],
      supported_shapes: [:scalar, :wide],
      supports_watermarks?: false,
      completeness: :unknown
    })
  end

  @spec probe(DataSource.t(), keyword()) :: SourceProbe.t()
  def probe(%DataSource{} = data_source, opts \\ []) when is_list(opts) do
    case metadata_value(data_source.metadata, :storage) do
      storage when storage in [:questdb, "questdb"] ->
        probe_questdb(data_source, opts)

      storage ->
        SourceProbe.unsupported(%{
          adapter: "telemetry",
          storage: storage || "unknown",
          reason: "telemetry adapter only has a live probe for QuestDB-backed sources"
        })
    end
  end

  @spec facts(PlannedSourceRequest.t(), keyword()) ::
          {:ok, SourceFacts.t()} | {:error, ResolveWarning.t()}
  def facts(%PlannedSourceRequest{} = request, opts \\ []) when is_list(opts) do
    source_binding = Keyword.get(opts, :source_binding)

    with :ok <- ensure_telemetry_source(request),
         {:ok, mission_id} <- required_request_context(request, :mission_id),
         {:ok, organization_id} <- required_request_context(request, :organization_id),
         :ok <- ensure_observables(request.observables) do
      watermark = watermark(request, source_binding, organization_id, mission_id, opts)

      {:ok,
       SourceFacts.new(%{
         source_binding: source_binding && source_binding.binding,
         data_source: source_binding && source_binding.data_source,
         watermark: watermark,
         data_revision: Keyword.get(opts, :data_revision),
         correction_cursor: Keyword.get(opts, :correction_cursor),
         backfill_cursor: Keyword.get(opts, :backfill_cursor),
         source_health: Keyword.get(opts, :source_health, :healthy),
         meta: %{
           logical_source: :telemetry,
           source_binding_id: source_binding_id(source_binding),
           data_source_id: data_source_id(request, source_binding)
         }
       })}
    else
      {:warning, warning} -> {:error, warning}
    end
  end

  @spec resolve(PlannedSourceRequest.t(), keyword()) :: SourceResult.t()
  def resolve(%PlannedSourceRequest{} = request, opts \\ []) when is_list(opts) do
    source_binding = Keyword.get(opts, :source_binding)
    overlay_warnings = overlay_warnings(request)

    with :ok <- ensure_telemetry_source(request),
         :ok <- ensure_supported_sampling(request, source_binding),
         {:ok, mission_id} <- required_request_context(request, :mission_id),
         {:ok, organization_id} <- required_request_context(request, :organization_id),
         :ok <- ensure_observables(request.observables) do
      watermark = watermark(request, source_binding, organization_id, mission_id, opts)

      request_warnings =
        overlay_warnings ++ watermark_warnings(request, source_binding, watermark)

      {frames, mode_warnings, supported_capability} =
        resolve_frames(
          request,
          source_binding,
          organization_id,
          mission_id,
          opts,
          request_warnings
        )

      warnings = request_warnings ++ mode_warnings

      SourceResult.new(%{
        request_id: request.request_id,
        frames: frames,
        warnings: warnings,
        watermarks: [watermark],
        meta: %{
          logical_source: :telemetry,
          source_binding_id: source_binding_id(source_binding),
          data_source_id: data_source_id(request, source_binding),
          supported_capability: supported_capability,
          returned_frame_count: length(frames),
          telemetry_revision_dependency: telemetry_revision_dependency(frames),
          degraded?: degraded?(warnings)
        }
      })
    else
      {:warning, warning} ->
        request_warnings = overlay_warnings ++ unknown_watermark_warnings(request)

        SourceResult.new(%{
          request_id: request.request_id,
          warnings: request_warnings ++ [warning],
          watermarks: [unknown_watermark(request, source_binding)],
          meta: %{
            logical_source: request.logical_source,
            source_binding_id: source_binding_id(source_binding),
            data_source_id: data_source_id(request, source_binding),
            supported_capability: supported_capability(request),
            returned_frame_count: 0,
            degraded?: true
          }
        })
    end
  end

  defp ensure_telemetry_source(%PlannedSourceRequest{logical_source: :telemetry}), do: :ok

  defp ensure_telemetry_source(%PlannedSourceRequest{} = request) do
    {:warning,
     warning(
       request,
       :unsupported_logical_source,
       :error,
       "Telemetry adapter cannot resolve source",
       %{
         logical_source: request.logical_source
       }
     )}
  end

  defp probe_questdb(%DataSource{} = data_source, opts) do
    if questdb_probe_enabled?(opts) do
      with {:ok, _body} <- questdb_probe_exec("SELECT 1", opts),
           {:ok, schema_metadata} <- questdb_schema_probe_metadata(opts) do
        SourceProbe.healthy(
          :source_probe_succeeded,
          Map.merge(questdb_probe_metadata(data_source, opts), schema_metadata),
          probe_kind: :adapter
        )
      else
        {:schema_error, reason, schema_metadata} ->
          SourceProbe.degraded(
            :source_schema_probe_failed,
            questdb_probe_metadata(data_source, opts)
            |> Map.merge(schema_metadata)
            |> Map.merge(questdb_schema_diagnostic_metadata(reason, schema_metadata))
            |> Map.put(:adapter_error, questdb_safe_error(reason)),
            probe_kind: :adapter
          )

        {:error, reason} ->
          SourceProbe.unavailable(
            :source_connection_failed,
            questdb_probe_metadata(data_source, opts)
            |> Map.merge(questdb_connection_diagnostic_metadata(reason))
            |> Map.put(:adapter_error, questdb_safe_error(reason)),
            probe_kind: :adapter
          )
      end
    else
      SourceProbe.unsupported(
        Map.merge(questdb_probe_metadata(data_source, opts), %{
          probe_enabled?: false,
          reason: "QuestDB live probe is disabled for this environment"
        })
      )
    end
  end

  defp questdb_schema_probe_metadata(opts) do
    case questdb_probe_exec(questdb_schema_probe_sql(), opts) do
      {:ok, result} ->
        columns = questdb_result_columns(result)
        missing = questdb_probe_columns() -- columns

        if missing == [] do
          {:ok,
           %{
             questdb_schema_probe?: true,
             questdb_schema_table: "telemetry_observations",
             questdb_schema_columns: columns,
             adapter_reported_capabilities: %{
               latest?: true,
               range_scan?: true,
               bounded_history?: true,
               native_decimation?: true,
               watermarks?: true
             }
           }}
        else
          {:schema_error, {:missing_columns, missing},
           %{
             questdb_schema_probe?: true,
             questdb_schema_table: "telemetry_observations",
             questdb_schema_columns: columns,
             questdb_schema_missing_columns: missing,
             adapter_reported_capabilities: %{
               latest?: true,
               range_scan?: false,
               bounded_history?: false,
               native_decimation?: false,
               watermarks?: false
             }
           }}
        end

      {:error, reason} ->
        {:schema_error, reason,
         %{
           questdb_schema_probe?: false,
           questdb_schema_table: "telemetry_observations",
           adapter_reported_capabilities: %{
             latest?: false,
             range_scan?: false,
             bounded_history?: false,
             native_decimation?: false,
             watermarks?: false
           }
         }}
    end
  end

  defp questdb_schema_probe_sql do
    "SELECT #{questdb_probe_columns() |> Enum.join(", ")} FROM telemetry_observations LIMIT 0"
  end

  defp questdb_probe_columns do
    writer_columns =
      ObservationRow.columns()
      |> Enum.map(&Atom.to_string/1)

    (ObservationReader.select_columns() ++ writer_columns)
    |> Enum.uniq()
  end

  defp questdb_result_columns(%{"columns" => columns}) when is_list(columns) do
    columns
    |> Enum.map(fn
      %{"name" => name} when is_binary(name) -> name
      %{name: name} when is_binary(name) -> name
      name when is_binary(name) -> name
      _other -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp questdb_result_columns(_result), do: []

  defp questdb_safe_error({:http_error, status, _body}),
    do: "{:http_error, #{status}, :redacted_body}"

  defp questdb_safe_error(reason) when is_map(reason), do: "adapter_error"
  defp questdb_safe_error(reason), do: inspect(reason)

  defp questdb_connection_diagnostic_metadata(reason) do
    {kind, remediation} =
      case questdb_reason_category(reason) do
        :authentication_failed -> {:authentication_failed, :check_credential_material}
        :http_error -> {:http_error, :check_questdb_http_api}
        :timeout -> {:connection_timeout, :check_questdb_endpoint}
        :unreachable -> {:connection_unreachable, :check_questdb_endpoint}
        _other -> {:connection_failed, :check_questdb_endpoint}
      end

    %{
      probe_diagnostic_kind: kind,
      probe_diagnostic_stage: :connection_test,
      probe_remediation: remediation
    }
  end

  defp questdb_schema_diagnostic_metadata({:missing_columns, missing}, _schema_metadata) do
    %{
      probe_diagnostic_kind: :schema_mismatch,
      probe_diagnostic_stage: :schema_validation,
      probe_remediation: :run_questdb_schema_migration,
      probe_diagnostic_detail: "missing_columns:#{Enum.join(missing, ",")}"
    }
  end

  defp questdb_schema_diagnostic_metadata(reason, _schema_metadata) do
    {kind, remediation} =
      case questdb_reason_category(reason) do
        :authentication_failed -> {:authentication_failed, :check_schema_probe_credentials}
        :http_error -> {:schema_query_failed, :check_questdb_http_api}
        :timeout -> {:schema_query_timeout, :check_questdb_schema_access}
        :unreachable -> {:schema_unavailable, :check_questdb_schema_access}
        _other -> {:schema_unavailable, :check_questdb_schema_access}
      end

    %{
      probe_diagnostic_kind: kind,
      probe_diagnostic_stage: :schema_query,
      probe_remediation: remediation
    }
  end

  defp questdb_reason_category({:http_error, status, _body}) when status in [401, 403],
    do: :authentication_failed

  defp questdb_reason_category({:http_error, _status, _body}), do: :http_error
  defp questdb_reason_category(:econnrefused), do: :unreachable
  defp questdb_reason_category(:nxdomain), do: :unreachable
  defp questdb_reason_category(:timeout), do: :timeout

  defp questdb_reason_category(%{reason: reason}) when is_atom(reason),
    do: questdb_reason_category(reason)

  defp questdb_reason_category(reason) when is_exception(reason) do
    reason
    |> Exception.message()
    |> String.downcase()
    |> questdb_reason_category_from_text()
  end

  defp questdb_reason_category(reason) when is_binary(reason) do
    reason
    |> String.downcase()
    |> questdb_reason_category_from_text()
  end

  defp questdb_reason_category(reason) do
    reason
    |> inspect()
    |> String.downcase()
    |> questdb_reason_category_from_text()
  end

  defp questdb_reason_category_from_text(text) do
    cond do
      questdb_auth_error_text?(text) -> :authentication_failed
      questdb_timeout_text?(text) -> :timeout
      questdb_unreachable_text?(text) -> :unreachable
      questdb_http_error_text?(text) -> :http_error
      true -> :unknown
    end
  end

  defp questdb_auth_error_text?(text) do
    text =~ "401" or text =~ "403" or text =~ "unauthorized" or text =~ "forbidden"
  end

  defp questdb_timeout_text?(text), do: text =~ "timeout"

  defp questdb_unreachable_text?(text) do
    text =~ "econnrefused" or text =~ "nxdomain" or text =~ "closed"
  end

  defp questdb_http_error_text?(text), do: text =~ "http_error"

  defp questdb_probe_exec(sql, opts) do
    config = Application.get_env(:cadence, :dashboard_source_probe, [])

    exec_fun =
      Keyword.get(opts, :questdb_exec_fun) ||
        Keyword.get(config, :questdb_exec_fun) ||
        (&RestClient.exec/2)

    exec_fun.(sql, questdb_probe_opts(opts))
  end

  defp questdb_probe_metadata(%DataSource{} = data_source, opts) do
    config = Application.get_env(:cadence, :dashboard_source_probe, [])

    %{
      adapter: "telemetry",
      storage: "questdb",
      data_source_id: data_source.data_source_id,
      http_endpoint: questdb_http_endpoint(opts, config),
      connection_profile?: is_map(Keyword.get(opts, :source_connection_profile))
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp questdb_probe_opts(opts) do
    config = Application.get_env(:cadence, :dashboard_source_probe, [])

    [
      http_endpoint: questdb_http_endpoint(opts, config),
      timeout: Keyword.get(opts, :questdb_timeout, Keyword.get(config, :questdb_timeout, 2_000)),
      headers: questdb_auth_headers(opts)
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == [] end)
  end

  defp questdb_auth_headers(opts) do
    material = Keyword.get(opts, :source_connection_material, [])
    headers = material |> Keyword.get(:headers, []) |> normalize_headers()

    cond do
      bearer_token = Keyword.get(material, :bearer_token) ->
        [{"authorization", "Bearer #{bearer_token}"} | headers]

      username = Keyword.get(material, :username) ->
        case Keyword.get(material, :password) do
          password when is_binary(password) ->
            encoded = Base.encode64("#{username}:#{password}")
            [{"authorization", "Basic #{encoded}"} | headers]

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

  defp questdb_http_endpoint(opts, config) do
    Keyword.get(opts, :questdb_http_endpoint) ||
      opts
      |> Keyword.get(:source_connection_material, [])
      |> Keyword.get(:http_endpoint) ||
      opts
      |> Keyword.get(:source_connection_profile, %{})
      |> metadata_value(:http_endpoint) ||
      Keyword.get(config, :questdb_http_endpoint)
  end

  defp questdb_probe_enabled?(opts) do
    config = Application.get_env(:cadence, :dashboard_source_probe, [])
    Keyword.get(opts, :questdb_probe?, Keyword.get(config, :questdb_enabled?, false))
  end

  defp ensure_supported_sampling(%PlannedSourceRequest{} = request, source_binding) do
    mode = sampling_mode(request)

    if mode in supported_sampling_modes(source_binding) do
      :ok
    else
      {:warning,
       warning(
         request,
         :unsupported_sampling,
         :warning,
         "Telemetry source cannot resolve requested sampling mode",
         %{
           requested_mode: mode,
           supported_modes: supported_sampling_modes(source_binding)
         }
       )}
    end
  end

  defp supported_sampling_modes(source_binding) do
    if native_decimation?(source_binding) do
      @supported_sampling_modes ++ @native_decimated_sampling_modes
    else
      @supported_sampling_modes
    end
  end

  defp ensure_observables([observable | _rest]) when is_binary(observable), do: :ok

  defp ensure_observables(_observables) do
    {:warning,
     %ResolveWarning{
       code: :missing_observables,
       severity: :error,
       scope: :dashboard,
       message: "Telemetry source request does not include observables"
     }}
  end

  defp metadata_value(metadata, key) when is_map(metadata) do
    Map.get(metadata, key, Map.get(metadata, Atom.to_string(key)))
  end

  defp metadata_value(_metadata, _key), do: nil

  defp first_metadata_value(metadata, keys) when is_map(metadata) and is_list(keys) do
    Enum.find_value(keys, &metadata_value(metadata, &1))
  end

  defp first_metadata_value(_metadata, _keys), do: nil

  defp resolve_frames(
         %PlannedSourceRequest{} = request,
         source_binding,
         organization_id,
         mission_id,
         opts,
         request_warnings
       ) do
    data_view_warnings = data_view_warnings(request)
    request_warnings = request_warnings ++ data_view_warnings

    case sampling_mode(request) do
      :latest ->
        latest_opts = latest_opts(request, source_binding, opts)
        time_warnings = latest_time_warnings(request)
        latest_fun = Keyword.get(opts, :latest_fun, &default_latest/4)

        {frames, revision_warnings} =
          Enum.map(request.observables, fn observable_id ->
            sample = latest_fun.(organization_id, mission_id, observable_id, latest_opts)

            {
              latest_frame(
                request,
                source_binding,
                observable_id,
                sample,
                request_warnings ++ time_warnings,
                source_filter_context(latest_opts)
              ),
              List.wrap(sample)
            }
          end)
          |> resolve_revision_state(request, source_binding, organization_id, mission_id, opts)

        frames =
          annotate_active_historical_workflows(
            frames,
            request,
            source_binding,
            organization_id,
            mission_id,
            opts
          )

        partial_warnings =
          partial_coverage_warnings(request, source_binding, frames)

        frames =
          annotate_frame_warning_codes(frames, partial_warnings)

        {frames, data_view_warnings ++ time_warnings ++ revision_warnings ++ partial_warnings,
         :latest_value}

      mode when mode in @history_sampling_modes ->
        {history_opts, time_warnings} = history_opts(request, source_binding, opts)
        history_fun = Keyword.get(opts, :history_fun, &default_history/4)

        case resolve_history_entries(
               request,
               source_binding,
               organization_id,
               mission_id,
               history_opts,
               history_fun,
               request_warnings ++ time_warnings
             ) do
          {:ok, entries} ->
            bounded_history_success_result(
              entries,
              request,
              source_binding,
              organization_id,
              mission_id,
              opts,
              data_view_warnings,
              time_warnings
            )

          {:error, observable_id, reason} ->
            bounded_history_error_result(
              request,
              source_binding,
              observable_id,
              reason,
              data_view_warnings,
              request_warnings,
              time_warnings
            )
        end

      :decimated_envelope ->
        {decimated_opts, time_warnings} = decimated_history_opts(request, source_binding, opts)
        aggregate_warnings = native_aggregate_semantics_warnings(request)

        decimated_history_fun =
          Keyword.get(opts, :decimated_history_fun, &default_decimated_history/4)

        case resolve_decimated_frames(
               request,
               source_binding,
               organization_id,
               mission_id,
               decimated_opts,
               decimated_history_fun,
               request_warnings ++ time_warnings ++ aggregate_warnings
             ) do
          {:ok, frames} ->
            partial_warnings =
              partial_coverage_warnings(request, source_binding, frames)

            frames =
              annotate_active_historical_workflows(
                frames,
                request,
                source_binding,
                organization_id,
                mission_id,
                opts
              )

            {frames,
             data_view_warnings ++ time_warnings ++ aggregate_warnings ++ partial_warnings,
             :native_decimated_envelope}

          {:error, reason} ->
            source_warning =
              source_query_failure_warning(
                request,
                source_binding,
                nil,
                :native_decimated_history,
                :native_decimation,
                reason
              )

            {[],
             data_view_warnings ++
               request_warnings ++
               time_warnings ++
               aggregate_warnings ++
               [source_warning], :native_decimated_envelope}
        end
    end
  end

  defp bounded_history_success_result(
         entries,
         %PlannedSourceRequest{} = request,
         source_binding,
         organization_id,
         mission_id,
         opts,
         data_view_warnings,
         time_warnings
       ) do
    {frames, revision_warnings} =
      entries
      |> Enum.map(fn {frame, samples, _history_warnings} -> {frame, samples} end)
      |> resolve_revision_state(request, source_binding, organization_id, mission_id, opts)

    frames =
      annotate_active_historical_workflows(
        frames,
        request,
        source_binding,
        organization_id,
        mission_id,
        opts
      )

    history_warnings =
      entries
      |> Enum.flat_map(fn {_frame, _samples, history_warnings} -> history_warnings end)
      |> Enum.uniq_by(&warning_key/1)

    partial_warnings =
      partial_coverage_warnings(request, source_binding, frames)

    {frames,
     data_view_warnings ++
       time_warnings ++
       history_warnings ++
       revision_warnings ++
       partial_warnings, bounded_history_capability(request)}
  end

  defp bounded_history_error_result(
         %PlannedSourceRequest{} = request,
         source_binding,
         observable_id,
         reason,
         data_view_warnings,
         request_warnings,
         time_warnings
       ) do
    source_warning =
      source_query_failure_warning(
        request,
        source_binding,
        observable_id,
        :bounded_history,
        bounded_history_capability(request),
        reason
      )

    {[], data_view_warnings ++ request_warnings ++ time_warnings ++ [source_warning],
     bounded_history_capability(request)}
  end

  defp resolve_history_entries(
         %PlannedSourceRequest{} = request,
         source_binding,
         organization_id,
         mission_id,
         history_opts,
         history_fun,
         warnings
       ) do
    request.observables
    |> Enum.reduce_while({:ok, []}, fn observable_id, {:ok, entries} ->
      history_result =
        history_fun.(organization_id, mission_id, observable_id, history_opts)

      case normalize_history_result(history_result) do
        {:ok, samples, diagnostics} ->
          history_warnings = history_diagnostics_warnings(request, observable_id, diagnostics)

          entry =
            {
              history_frame(
                request,
                source_binding,
                observable_id,
                samples,
                warnings ++ history_warnings,
                diagnostics,
                source_filter_context(history_opts)
              ),
              samples,
              history_warnings
            }

          {:cont, {:ok, [entry | entries]}}

        {:error, reason} ->
          {:halt, {:error, observable_id, reason}}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      {:error, observable_id, reason} -> {:error, observable_id, reason}
    end
  end

  defp resolve_decimated_frames(
         %PlannedSourceRequest{} = request,
         source_binding,
         organization_id,
         mission_id,
         opts,
         decimated_history_fun,
         warnings
       ) do
    request.observables
    |> Enum.reduce_while({:ok, []}, fn observable_id, {:ok, frames} ->
      case resolve_decimated_frame(
             request,
             source_binding,
             organization_id,
             mission_id,
             observable_id,
             opts,
             decimated_history_fun,
             warnings
           ) do
        {:ok, frame} -> {:cont, {:ok, [frame | frames]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, frames} -> {:ok, Enum.reverse(frames)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_decimated_frame(
         %PlannedSourceRequest{} = request,
         source_binding,
         organization_id,
         mission_id,
         observable_id,
         opts,
         decimated_history_fun,
         warnings
       ) do
    decimated_history_fun.(organization_id, mission_id, observable_id, opts)
    |> normalize_decimated_history_result()
    |> decimated_frame_result(request, source_binding, observable_id, warnings, opts)
  end

  defp decimated_frame_result(
         {:ok, buckets, diagnostics},
         request,
         source_binding,
         observable_id,
         warnings,
         opts
       ) do
    frame =
      decimated_frame(
        request,
        source_binding,
        observable_id,
        buckets,
        warnings,
        diagnostics,
        source_filter_context(opts)
      )

    {:ok, frame}
  end

  defp decimated_frame_result(
         {:error, reason},
         _request,
         _source_binding,
         _observable_id,
         _warnings,
         _opts
       ) do
    {:error, reason}
  end

  defp normalize_history_result({:ok, %{samples: samples, diagnostics: diagnostics}})
       when is_list(samples) and is_map(diagnostics) do
    {:ok, samples, diagnostics}
  end

  defp normalize_history_result(%{samples: samples, diagnostics: diagnostics})
       when is_list(samples) and is_map(diagnostics) do
    {:ok, samples, diagnostics}
  end

  defp normalize_history_result({:error, reason}), do: {:error, reason}
  defp normalize_history_result({:ok, samples}) when is_list(samples), do: {:ok, samples, %{}}
  defp normalize_history_result(samples) when is_list(samples), do: {:ok, samples, %{}}
  defp normalize_history_result(other), do: {:error, {:invalid_history_result, other}}

  defp normalize_decimated_history_result({:ok, %{buckets: buckets, diagnostics: diagnostics}})
       when is_list(buckets) and is_map(diagnostics) do
    {:ok, buckets, diagnostics}
  end

  defp normalize_decimated_history_result(%{buckets: buckets, diagnostics: diagnostics})
       when is_list(buckets) and is_map(diagnostics) do
    {:ok, buckets, diagnostics}
  end

  defp normalize_decimated_history_result({:error, reason}), do: {:error, reason}

  defp normalize_decimated_history_result({:ok, buckets}) when is_list(buckets),
    do: {:ok, buckets, %{}}

  defp normalize_decimated_history_result(buckets) when is_list(buckets), do: {:ok, buckets, %{}}

  defp normalize_decimated_history_result(other),
    do: {:error, {:invalid_decimated_history_result, other}}

  defp history_diagnostics_warnings(
         %PlannedSourceRequest{} = request,
         observable_id,
         %{candidate_window_exhausted?: true} = diagnostics
       ) do
    [
      %ResolveWarning{
        code: :candidate_window_exhausted,
        severity: :warning,
        scope: :frame,
        frame_id: "#{request.request_id}:#{observable_id}",
        message: "Telemetry history candidate window was exhausted before selection completed",
        details:
          diagnostics
          |> Map.merge(%{
            source_request_id: request.request_id,
            observable_id: observable_id,
            point_id: observable_id
          })
          |> put_telemetry_warning_actions(request, observable_id),
        links: DataLinks.request_observable_links(request, source: :warning)
      }
    ]
  end

  defp history_diagnostics_warnings(%PlannedSourceRequest{}, _observable_id, _diagnostics),
    do: []

  defp partial_coverage_warnings(
         %PlannedSourceRequest{} = request,
         source_binding,
         frames
       )
       when is_list(frames) do
    empty_observables =
      frames
      |> Enum.filter(&empty_frame?/1)
      |> Enum.map(&frame_observable_id/1)
      |> Enum.reject(&is_nil/1)

    returned_observables =
      frames
      |> Enum.reject(&empty_frame?/1)
      |> Enum.map(&frame_observable_id/1)
      |> Enum.reject(&is_nil/1)

    if empty_observables != [] and returned_observables != [] do
      [
        warning(
          request,
          :partial_data,
          :warning,
          "Telemetry range source returned partial data",
          %{
            logical_source: :telemetry,
            requested_observables: request.observables,
            returned_observables: returned_observables,
            empty_observables: empty_observables,
            source_binding_id: source_binding_id(source_binding),
            data_source_id: data_source_id(request, source_binding),
            realm: realm(request, source_binding),
            time_mode: time_mode(request),
            time_axis: :receipt_time
          }
        )
      ]
    else
      []
    end
  end

  defp partial_coverage_warnings(%PlannedSourceRequest{}, _source_binding, _frames),
    do: []

  defp annotate_frame_warning_codes(frames, []), do: frames

  defp annotate_frame_warning_codes(frames, warnings)
       when is_list(frames) and is_list(warnings) do
    warning_codes =
      warnings
      |> Enum.map(& &1.code)
      |> Enum.reject(&is_nil/1)

    Enum.map(frames, &annotate_frame_warning_codes(&1, warning_codes))
  end

  defp annotate_frame_warning_codes(%Frame{meta: meta} = frame, warning_codes)
       when is_map(meta) do
    existing_codes =
      meta
      |> Map.get(:warning_codes, Map.get(meta, "warning_codes", []))
      |> List.wrap()

    %Frame{
      frame
      | meta: Map.put(meta, :warning_codes, Enum.uniq(existing_codes ++ warning_codes))
    }
  end

  defp annotate_frame_warning_codes(frame, _warning_codes), do: frame

  defp empty_frame?(%Frame{meta: meta}) when is_map(meta) do
    Map.get(meta, :returned_points, Map.get(meta, "returned_points", 0)) == 0
  end

  defp empty_frame?(%Frame{}), do: true

  defp frame_observable_id(%Frame{meta: meta}) when is_map(meta) do
    Map.get(meta, :observable_id, Map.get(meta, "observable_id"))
  end

  defp frame_observable_id(%Frame{}), do: nil

  defp overlay_warnings(%PlannedSourceRequest{overlays: []}), do: []
  defp overlay_warnings(%PlannedSourceRequest{overlays: nil}), do: []

  defp overlay_warnings(%PlannedSourceRequest{} = request) do
    [
      warning(
        request,
        :capability_fallback,
        :info,
        "Telemetry source does not resolve overlays yet",
        %{
          requested_overlays: request.overlays,
          unresolved_capability: :overlays
        }
      )
    ]
  end

  defp watermark_warnings(
         %PlannedSourceRequest{},
         _source_binding,
         %SourceWatermark{confidence: confidence}
       )
       when confidence in [:authoritative, :best_effort],
       do: []

  defp watermark_warnings(
         %PlannedSourceRequest{} = request,
         source_binding,
         %SourceWatermark{} = watermark
       ) do
    unknown_watermark_warnings(request, source_binding, watermark)
  end

  defp unknown_watermark_warnings(%PlannedSourceRequest{} = request) do
    unknown_watermark_warnings(request, nil, nil)
  end

  defp unknown_watermark_warnings(
         %PlannedSourceRequest{} = request,
         source_binding,
         %SourceWatermark{} = watermark
       ) do
    details =
      case watermark_errors(watermark) do
        [{observable_id, reason} | _rest] ->
          source_query_failure_details(
            request,
            source_binding,
            observable_id,
            :watermark,
            :source_watermark,
            reason
          )

        [] ->
          %{unresolved_capability: :source_watermark}
      end

    [
      warning(
        request,
        :watermark_unknown,
        :info,
        "Telemetry source watermark confidence is unknown",
        details
      )
    ]
  end

  defp unknown_watermark_warnings(%PlannedSourceRequest{} = request, _source_binding, _watermark) do
    [
      warning(
        request,
        :watermark_unknown,
        :info,
        "Telemetry source watermark confidence is unknown",
        %{unresolved_capability: :source_watermark}
      )
    ]
  end

  defp watermark_errors(%SourceWatermark{meta: %{point_watermarks: point_watermarks}})
       when is_map(point_watermarks) do
    point_watermarks
    |> Enum.flat_map(fn {observable_id, result} ->
      case watermark_error(result) do
        nil -> []
        reason -> [{observable_id, reason}]
      end
    end)
  end

  defp watermark_errors(%SourceWatermark{}), do: []

  defp watermark_error(result) when is_map(result) do
    context_value(result, :error)
  end

  defp watermark_error(_result), do: nil

  defp native_aggregate_semantics_warnings(%PlannedSourceRequest{} = request) do
    [
      warning(
        request,
        :physical_aggregate_semantics,
        :info,
        "Native telemetry aggregates use physical storage semantics",
        %{
          canonical_mode: :physical,
          aggregate_semantics: :physical_as_recorded,
          affected_products: [:native_decimated_envelope, :source_watermark],
          future_mode: :effective_canonical
        }
      )
    ]
  end

  defp source_query_failure_warning(
         %PlannedSourceRequest{} = request,
         source_binding,
         observable_id,
         query_kind,
         unresolved_capability,
         reason
       ) do
    warning(
      request,
      :source_unavailable,
      :error,
      source_query_failure_message(query_kind),
      source_query_failure_details(
        request,
        source_binding,
        observable_id,
        query_kind,
        unresolved_capability,
        reason
      )
    )
  end

  defp source_query_failure_message(:native_decimated_history),
    do: "Telemetry data source cannot execute native decimated history"

  defp source_query_failure_message(:watermark),
    do: "Telemetry data source cannot read source watermark"

  defp source_query_failure_message(_query_kind),
    do: "Telemetry data source cannot execute bounded history"

  defp source_query_failure_details(
         %PlannedSourceRequest{} = request,
         source_binding,
         observable_id,
         query_kind,
         unresolved_capability,
         reason
       ) do
    %{
      logical_source: :telemetry,
      source_empty_reason: :source_query_failed,
      source_query_kind: query_kind,
      unresolved_capability: unresolved_capability,
      reason: format_reason(reason),
      observable_id: observable_id || List.first(List.wrap(request.observables)),
      point_id: observable_id || List.first(List.wrap(request.observables)),
      data_source_id: data_source_id(request, source_binding),
      source_binding_id: source_binding_id(source_binding),
      realm: realm(request, source_binding),
      dataset: dataset(source_binding),
      requested_sampling: sampling_mode(request)
    }
    |> SourceActions.put_source_request_context(request, :telemetry)
    |> SourceActions.put_source_warning_actions()
  end

  defp data_view_warnings(%PlannedSourceRequest{} = request) do
    case requested_data_view(request) do
      :canonical ->
        []

      :as_recorded ->
        [
          warning(
            request,
            :as_recorded_view,
            :info,
            "Telemetry source is using as-recorded data view",
            data_view_warning_details(request, :as_recorded)
          )
        ]

      :all_revisions ->
        [
          warning(
            request,
            :all_revisions_view,
            :warning,
            "Telemetry source is showing all observation revisions",
            data_view_warning_details(request, :all_revisions)
          )
        ]

      :recomputed ->
        [
          warning(
            request,
            :recomputed_values,
            :warning,
            "Telemetry source is using recomputed data view semantics",
            data_view_warning_details(request, :recomputed)
          )
        ]
    end
  end

  defp data_view_warning_details(%PlannedSourceRequest{} = request, data_view) do
    %{
      data_view: data_view,
      canonical_default?: false,
      point_id: List.first(List.wrap(request.observables)),
      observable_id: List.first(List.wrap(request.observables))
    }
  end

  defp required_request_context(%PlannedSourceRequest{} = request, key) do
    case request_context_value(request, key) do
      value when is_binary(value) and value != "" ->
        {:ok, value}

      _other ->
        {:warning,
         %ResolveWarning{
           code: missing_context_code(key),
           severity: :error,
           scope: :dashboard,
           message: "Telemetry source request is missing required context",
           details: %{required_context: key}
         }}
    end
  end

  defp missing_context_code(:organization_id), do: :missing_tenant_context
  defp missing_context_code(:mission_id), do: :missing_mission_context

  defp request_context_value(%PlannedSourceRequest{organization_id: value}, :organization_id)
       when is_binary(value) and value != "",
       do: value

  defp request_context_value(%PlannedSourceRequest{mission_id: value}, :mission_id)
       when is_binary(value) and value != "",
       do: value

  defp request_context_value(%PlannedSourceRequest{} = request, key) do
    context_value(request.scope_context, key)
  end

  defp selection_policy_opts(%PlannedSourceRequest{} = request) do
    [
      selection_view:
        DataContext.source_value(request.data_context, request.logical_source, :view) ||
          first_context_value(request.data_context, [
            :selection_view,
            :view,
            :data_view,
            :data_management_view
          ]),
      validity_state: context_value(request.data_context, :validity_state)
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
    |> SelectionPolicy.query_opts()
  end

  defp requested_data_view(%PlannedSourceRequest{} = request) do
    view =
      DataContext.source_value(request.data_context, request.logical_source, :view) ||
        first_context_value(request.data_context, [
          :selection_view,
          :view,
          :data_view,
          :data_management_view
        ])

    SelectionPolicy.view(selection_view: view)
  end

  defp analysis_basis(%PlannedSourceRequest{} = request) do
    case requested_data_view(request) do
      :recomputed -> :recomputed_analysis
      _observed_view -> :observed_fact
    end
  end

  defp history_opts(%PlannedSourceRequest{} = request, source_binding, source_opts) do
    {time_opts, time_warnings} = bounded_history_time_opts(request, source_opts)

    opts =
      [
        realm: realm(request, source_binding),
        replay_run_id: replay_run_id(request),
        data_source_id: data_source_id(request, source_binding),
        source_binding_id: source_binding_id(source_binding),
        dataset: dataset(source_binding),
        spacecraft_id: spacecraft_id(request.scope_context),
        source_endpoint_ids: source_endpoint_ids(request, source_opts),
        limit: raw_point_limit(request),
        order: :asc
      ]
      |> Kernel.++(time_opts)
      |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)

    {opts ++ selection_policy_opts(request) ++ connection_opts(source_opts), time_warnings}
  end

  defp decimated_history_opts(%PlannedSourceRequest{} = request, source_binding, source_opts) do
    {opts, time_warnings} = history_opts(request, source_binding, source_opts)

    decimation_opts =
      [
        target_points: target_points(request),
        bucket_width_ms: bucket_width_ms(request),
        decimation: :native_min_max_envelope
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    {opts ++ decimation_opts, time_warnings}
  end

  defp latest_opts(%PlannedSourceRequest{} = request, source_binding, opts) do
    [
      realm: realm(request, source_binding),
      replay_run_id: replay_run_id(request),
      data_source_id: data_source_id(request, source_binding),
      source_binding_id: source_binding_id(source_binding),
      dataset: dataset(source_binding),
      spacecraft_id: spacecraft_id(request.scope_context),
      source_endpoint_ids: source_endpoint_ids(request, opts),
      to_receipt_time: latest_as_of_receipt_time(request)
    ]
    |> Kernel.++(selection_policy_opts(request))
    |> Kernel.++(connection_opts(opts))
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
  end

  defp connection_opts(opts) when is_list(opts) do
    opts
    |> Keyword.take([
      :http_endpoint,
      :headers,
      :source_connection_profile,
      :source_connection_material
    ])
    |> Enum.reject(fn
      {_key, nil} -> true
      {_key, ""} -> true
      {_key, []} -> true
      _entry -> false
    end)
  end

  defp connection_opts(_opts), do: []

  defp receipt_time_bounds(%PlannedSourceRequest{} = request) do
    {time_bounds, warnings} = bounded_history_time_opts(request)

    {
      Keyword.get(time_bounds, :from_receipt_time),
      Keyword.get(time_bounds, :to_receipt_time),
      warnings
    }
  end

  defp bounded_history_time_opts(%PlannedSourceRequest{} = request) do
    requested_axis = time_axis(request)
    effective_axis = effective_bounded_history_time_axis(request, [])
    from_time = first_context_value(request.time_context, [:from, :start, :start_time])
    to_time = first_context_value(request.time_context, [:to, :end, :end_time])

    bounded_history_time_opts_for_axis(
      request,
      requested_axis,
      effective_axis,
      from_time,
      to_time,
      []
    )
  end

  defp bounded_history_time_opts(%PlannedSourceRequest{} = request, source_opts) do
    requested_axis = time_axis(request)
    effective_axis = effective_bounded_history_time_axis(request, source_opts)
    from_time = first_context_value(request.time_context, [:from, :start, :start_time])
    to_time = first_context_value(request.time_context, [:to, :end, :end_time])

    bounded_history_time_opts_for_axis(
      request,
      requested_axis,
      effective_axis,
      from_time,
      to_time,
      source_opts
    )
  end

  defp effective_bounded_history_time_axis(%PlannedSourceRequest{} = request, source_opts) do
    requested_axis = time_axis(request)
    supported_axes = supported_time_axes(source_opts)

    cond do
      requested_axis in [nil, :receipt_time] ->
        :receipt_time

      requested_axis == :generation_time and supported_axes == [] ->
        :generation_time

      requested_axis == :generation_time and :generation_time in supported_axes ->
        :generation_time

      true ->
        :unsupported
    end
  end

  defp supported_time_axes(source_opts) when is_list(source_opts) do
    source_opts
    |> Keyword.get(:supported_time_axes, [])
    |> List.wrap()
    |> Enum.map(&normalize_atom/1)
    |> Enum.filter(&(&1 in [:generation_time, :receipt_time]))
    |> Enum.uniq()
  end

  defp supported_time_axes(_source_opts), do: []

  defp bounded_history_time_opts_for_axis(
         request,
         requested_axis,
         effective_axis,
         from_time,
         to_time,
         source_opts
       ) do
    case effective_axis do
      axis when axis in [nil, :receipt_time] ->
        {[
           time_axis: :receipt_time,
           from_receipt_time: from_time,
           to_receipt_time: to_time
         ], []}

      :generation_time ->
        {[
           time_axis: :generation_time,
           from_observed_at: from_time,
           to_observed_at: to_time
         ], []}

      :unsupported ->
        warning =
          warning(
            request,
            :unsupported_time_axis,
            :warning,
            "Telemetry source cannot serve the requested dashboard time axis",
            %{
              requested_axis: requested_axis,
              requested_time_axis: requested_axis,
              fallback_axis: :receipt_time,
              executed_time_axis: :receipt_time,
              supported_time_axes: supported_time_axes(source_opts),
              unsupported_capability: :time_axis
            }
          )

        {[
           time_axis: :receipt_time,
           from_receipt_time: from_time,
           to_receipt_time: to_time
         ], [warning]}
    end
  end

  defp latest_time_warnings(%PlannedSourceRequest{} = request) do
    cond do
      not time_range_requested?(request.time_context) ->
        []

      latest_as_of_supported?(request) ->
        []

      true ->
        [
          warning(
            request,
            :time_range_ignored,
            :warning,
            "Latest telemetry archive requests require a receipt-time upper bound for as-of resolution",
            %{
              requested_time_mode: context_value(request.time_context, :mode),
              requested_axis: time_axis(request),
              fallback: :latest_projection
            }
          )
        ]
    end
  end

  defp latest_as_of_receipt_time(%PlannedSourceRequest{} = request) do
    if latest_as_of_supported?(request) do
      first_context_value(request.time_context, [:to, :end, :end_time])
    end
  end

  defp latest_as_of_supported?(%PlannedSourceRequest{} = request) do
    requested_axis = time_axis(request)
    to_time = first_context_value(request.time_context, [:to, :end, :end_time])

    not is_nil(to_time) and requested_axis in [nil, :receipt_time]
  end

  defp latest_frame(
         %PlannedSourceRequest{} = request,
         source_binding,
         observable_id,
         sample,
         warnings,
         source_filter_context
       ) do
    value_type = value_type(request)
    samples = List.wrap(sample)
    values = Enum.map(samples, &sample_value(&1, value_type))
    times = Enum.map(samples, &sample_time/1)
    time_axis = latest_time_axis(sample)
    evidence = telemetry_evidence_refs(source_binding, samples)

    %Frame{
      frame_id: "#{request.request_id}:#{observable_id}",
      source: :telemetry,
      shape: :scalar,
      time_axis: time_axis,
      scope: request.scope_context,
      overlays: %{requested: request.overlays || []},
      fields: [
        %Field{
          name: "time",
          kind: :time,
          values: times,
          metadata: %{axis: time_axis}
        },
        %Field{
          name: observable_id,
          kind: field_kind(values),
          values: values,
          metadata: field_metadata(request, source_binding, observable_id, value_type, samples)
        }
      ],
      meta:
        %{
          source_request_id: request.request_id,
          observable_id: observable_id,
          point_id: observable_id,
          logical_source: :telemetry,
          source_binding_id: source_binding_id(source_binding),
          dataset: dataset(source_binding),
          data_view: requested_data_view(request),
          analysis_basis: analysis_basis(request),
          sampling: :latest,
          value_type: value_type,
          latest?: true,
          realm: realm(request, source_binding),
          data_source_id: data_source_id(request, source_binding),
          replay_run_id: replay_run_id(request),
          returned_points: length(samples),
          truncated?: false,
          evidence: evidence,
          links:
            DataLinks.telemetry_links(request, observable_id, samples,
              source: :frame,
              source_binding: source_binding
            ),
          actions:
            telemetry_explore_actions(request, source_binding, observable_id, samples, :frame),
          warning_codes: Enum.map(warnings, & &1.code)
        }
        |> Map.merge(source_filter_context)
    }
  end

  defp history_frame(
         %PlannedSourceRequest{} = request,
         source_binding,
         observable_id,
         samples,
         warnings,
         diagnostics,
         source_filter_context
       ) do
    value_type = value_type(request)
    values = Enum.map(samples, &sample_value(&1, value_type))
    time_axis = bounded_history_frame_axis(request, source_filter_context)
    times = Enum.map(samples, &sample_time(&1, time_axis))
    evidence = telemetry_evidence_refs(source_binding, samples)

    %Frame{
      frame_id: "#{request.request_id}:#{observable_id}",
      source: :telemetry,
      shape: :wide,
      time_axis: time_axis,
      scope: request.scope_context,
      overlays: %{requested: request.overlays || []},
      fields: [
        %Field{
          name: "time",
          kind: :time,
          values: times,
          metadata: %{axis: time_axis}
        },
        %Field{
          name: observable_id,
          kind: field_kind(values),
          values: values,
          metadata: field_metadata(request, source_binding, observable_id, value_type, samples)
        }
      ],
      meta:
        %{
          source_request_id: request.request_id,
          observable_id: observable_id,
          point_id: observable_id,
          logical_source: :telemetry,
          source_binding_id: source_binding_id(source_binding),
          dataset: dataset(source_binding),
          data_view: requested_data_view(request),
          analysis_basis: analysis_basis(request),
          sampling: sampling_mode(request),
          value_type: value_type,
          realm: realm(request, source_binding),
          data_source_id: data_source_id(request, source_binding),
          replay_run_id: replay_run_id(request),
          returned_points: length(samples),
          truncated?: length(samples) >= raw_point_limit(request),
          evidence: evidence,
          links:
            DataLinks.telemetry_links(request, observable_id, samples,
              source: :frame,
              source_binding: source_binding
            ),
          actions:
            telemetry_explore_actions(request, source_binding, observable_id, samples, :frame),
          history_diagnostics: diagnostics,
          warning_codes: Enum.map(warnings, & &1.code)
        }
        |> Map.merge(source_filter_context)
    }
  end

  defp decimated_frame(
         %PlannedSourceRequest{} = request,
         source_binding,
         observable_id,
         buckets,
         warnings,
         diagnostics,
         source_filter_context
       ) do
    value_type = value_type(request)
    evidence = source_binding_interval_evidence_refs(source_binding)

    field_metadata =
      decimated_field_metadata(request, source_binding, observable_id, value_type, buckets)

    warning_codes = Enum.map(warnings, & &1.code)
    time_axis = bounded_history_frame_axis(request, source_filter_context)

    %Frame{
      frame_id: "#{request.request_id}:#{observable_id}",
      source: :telemetry,
      shape: :wide,
      time_axis: time_axis,
      scope: request.scope_context,
      overlays: %{requested: request.overlays || []},
      fields: [
        %Field{
          name: "bucket_start",
          kind: :time,
          values: Enum.map(buckets, &bucket_value(&1, :bucket_start)),
          metadata: %{axis: time_axis}
        },
        %Field{
          name: "bucket_end",
          kind: :time,
          values: Enum.map(buckets, &bucket_value(&1, :bucket_end)),
          metadata: %{axis: time_axis}
        },
        %Field{
          name: "#{observable_id}_min",
          kind: :number,
          values: Enum.map(buckets, &bucket_value(&1, :min)),
          metadata: field_metadata
        },
        %Field{
          name: "#{observable_id}_max",
          kind: :number,
          values: Enum.map(buckets, &bucket_value(&1, :max)),
          metadata: field_metadata
        },
        %Field{
          name: "#{observable_id}_value",
          kind: :number,
          values: Enum.map(buckets, &bucket_representative_value/1),
          metadata: field_metadata
        },
        %Field{
          name: "#{observable_id}_sample_count",
          kind: :number,
          values: Enum.map(buckets, &bucket_value(&1, :sample_count)),
          metadata: field_metadata
        }
      ],
      meta:
        %{
          source_request_id: request.request_id,
          observable_id: observable_id,
          point_id: observable_id,
          logical_source: :telemetry,
          source_binding_id: source_binding_id(source_binding),
          dataset: dataset(source_binding),
          data_view: requested_data_view(request),
          analysis_basis: analysis_basis(request),
          sampling: :decimated_envelope,
          decimation: :native_min_max_envelope,
          canonical_mode: :physical,
          aggregate_semantics: :physical_as_recorded,
          bucket_width_ms: bucket_width_ms(request),
          target_points: target_points(request),
          value_type: value_type,
          realm: realm(request, source_binding),
          data_source_id: data_source_id(request, source_binding),
          replay_run_id: replay_run_id(request),
          returned_points: length(buckets),
          truncated?: false,
          evidence: evidence,
          links:
            DataLinks.telemetry_links(request, observable_id, [],
              source: :frame,
              source_binding: source_binding
            ),
          actions: telemetry_explore_actions(request, source_binding, observable_id, [], :frame),
          decimated_diagnostics: diagnostics,
          warning_codes: warning_codes
        }
        |> Map.merge(source_filter_context)
    }
  end

  defp source_filter_context(opts) when is_list(opts) do
    %{}
    |> maybe_put_context(:time_axis, Keyword.get(opts, :time_axis))
    |> maybe_put_context(
      :source_endpoint_ids,
      opts
      |> Keyword.get(:source_endpoint_ids)
      |> normalize_source_endpoint_ids()
    )
  end

  defp source_filter_context(_opts), do: %{}

  defp field_metadata(
         %PlannedSourceRequest{} = request,
         source_binding,
         observable_id,
         value_type,
         samples
       ) do
    %{
      observable_id: observable_id,
      point_id: observable_id,
      data_view: requested_data_view(request),
      analysis_basis: analysis_basis(request),
      value_type: value_type,
      unit: sample_unit(samples),
      quality_states: samples |> Enum.map(& &1.quality_state) |> Enum.uniq(),
      sample_ids: Enum.map(samples, & &1.sample_id),
      evidence_ids: samples |> Enum.map(& &1.evidence_id) |> Enum.reject(&is_nil/1),
      evidence: telemetry_evidence_refs(source_binding, samples),
      links:
        DataLinks.telemetry_links(request, observable_id, samples,
          source: :field,
          source_binding: source_binding
        ),
      actions: telemetry_explore_actions(request, source_binding, observable_id, samples, :field)
    }
  end

  defp telemetry_evidence_refs(source_binding, samples) do
    (DataLinks.telemetry_sample_evidence_refs(samples) ++
       source_binding_interval_evidence_refs(source_binding))
    |> Enum.uniq_by(&evidence_ref_identity/1)
  end

  defp source_binding_interval_evidence_refs(%{binding_interval: interval})
       when not is_nil(interval) do
    DataLinks.source_binding_interval_evidence_refs([interval], source: :telemetry)
  end

  defp source_binding_interval_evidence_refs(_source_binding), do: []

  defp decimated_field_metadata(
         %PlannedSourceRequest{} = request,
         source_binding,
         observable_id,
         value_type,
         buckets
       ) do
    %{
      observable_id: observable_id,
      point_id: observable_id,
      data_view: requested_data_view(request),
      analysis_basis: analysis_basis(request),
      value_type: value_type,
      unit: bucket_unit(buckets),
      decimated?: true,
      decimation: :native_min_max_envelope,
      canonical_mode: :physical,
      aggregate_semantics: :physical_as_recorded,
      quality_states:
        buckets
        |> Enum.map(&bucket_value(&1, :worst_quality_state))
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq(),
      validity_states:
        buckets
        |> Enum.map(&bucket_value(&1, :worst_validity_state))
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq(),
      evidence: source_binding_interval_evidence_refs(source_binding),
      links:
        DataLinks.telemetry_links(request, observable_id, [],
          source: :field,
          source_binding: source_binding
        ),
      actions: telemetry_explore_actions(request, source_binding, observable_id, [], :field)
    }
  end

  defp sample_unit(samples) when is_list(samples) do
    Enum.find_value(samples, fn sample ->
      sample
      |> Map.get(:provenance, %{})
      |> first_metadata_value([:unit, :engineering_unit, :value_unit])
    end)
  end

  defp sample_unit(_samples), do: nil

  defp bucket_unit(buckets) when is_list(buckets) do
    Enum.find_value(buckets, fn bucket ->
      first_metadata_value(bucket, [:unit, :engineering_unit, :value_unit])
    end)
  end

  defp bucket_unit(_buckets), do: nil

  defp telemetry_explore_actions(request, source_binding, observable_id, samples, source) do
    telemetry_actions =
      TelemetryActions.explore_actions(request, observable_id, samples,
        source: source,
        source_binding: source_binding,
        action_id: "telemetry-explore:#{request.request_id}:#{observable_id}:#{source}"
      )

    source_inventory_action =
      SourceActions.source_inventory_action(
        %{
          logical_source: :telemetry,
          realm: realm(request, source_binding),
          data_source_id: data_source_id(request, source_binding),
          source_binding_id: source_binding_id(source_binding),
          dataset: dataset(source_binding)
        },
        source: source,
        inventory_action_id: "source-inventory:#{request.request_id}:#{observable_id}:#{source}"
      )

    [source_inventory_action | telemetry_actions]
    |> Enum.reject(&is_nil/1)
  end

  defp resolve_revision_state(
         frames_with_samples,
         %PlannedSourceRequest{} = request,
         source_binding,
         organization_id,
         mission_id,
         opts
       ) do
    identity_ids =
      frames_with_samples
      |> Enum.flat_map(fn {_frame, samples} -> Enum.flat_map(samples, &sample_identity_ids/1) end)
      |> Enum.uniq()

    case identity_ids do
      [] ->
        {Enum.map(frames_with_samples, &elem(&1, 0)), []}

      ids ->
        states_by_id =
          ids
          |> fetch_identity_states(
            identity_state_opts(request, source_binding, organization_id, mission_id),
            opts
          )
          |> Map.new(&{&1.observation_identity_id, &1})

        frames_with_samples
        |> Enum.map(fn {%Frame{} = frame, samples} ->
          states =
            samples
            |> Enum.flat_map(&sample_identity_ids/1)
            |> Enum.uniq()
            |> Enum.map(&Map.get(states_by_id, &1))
            |> Enum.reject(&is_nil/1)

          summary = TelemetryRevisionSummary.from_identity_states(states)
          frame = put_revision_summary(frame, summary)
          {frame, revision_warnings(request, frame, summary)}
        end)
        |> then(fn annotated ->
          {
            Enum.map(annotated, &elem(&1, 0)),
            annotated |> Enum.flat_map(&elem(&1, 1)) |> Enum.uniq_by(&warning_key/1)
          }
        end)
    end
  end

  defp fetch_identity_states(identity_ids, identity_state_opts, opts) do
    opts
    |> Keyword.get(:identity_states_fun, &TelemetryStorage.fetch_observation_identity_states/2)
    |> then(fn fetch_fun -> fetch_fun.(identity_ids, identity_state_opts) end)
    |> case do
      states when is_list(states) -> states
      {:ok, states} when is_list(states) -> states
      _other -> []
    end
  end

  defp annotate_active_historical_workflows(
         frames,
         %PlannedSourceRequest{} = request,
         source_binding,
         organization_id,
         mission_id,
         opts
       )
       when is_list(frames) do
    events =
      active_historical_workflow_events(
        request,
        source_binding,
        organization_id,
        mission_id,
        opts
      )

    active_workflows = latest_active_historical_workflows(events)
    terminal_outcomes = terminal_historical_workflow_outcomes(events)

    if active_workflows == [] and terminal_outcomes == [] do
      frames
    else
      Enum.map(frames, fn frame ->
        frame
        |> put_frame_active_historical_workflows(active_workflows)
        |> put_frame_historical_workflow_outcomes(terminal_outcomes)
      end)
    end
  end

  defp active_historical_workflow_events(
         %PlannedSourceRequest{} = request,
         source_binding,
         organization_id,
         mission_id,
         opts
       ) do
    {source_from, source_to, _warnings} = receipt_time_bounds(request)

    query_opts =
      [
        organization_id: organization_id,
        realm: realm(request, source_binding),
        replay_run_id: replay_run_id(request),
        data_source_id: data_source_id(request, source_binding),
        binding_id: source_binding_id(source_binding),
        source_from: source_from,
        source_to: source_to,
        limit: 1_000
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)

    case Keyword.fetch(opts, :backfill_lifecycle_events_fun) do
      {:ok, list_fun} when is_function(list_fun, 2) ->
        list_fun
        |> then(fn list_fun -> list_fun.(mission_id, query_opts) end)
        |> case do
          events when is_list(events) -> events
          {:ok, events} when is_list(events) -> events
          _other -> []
        end

      :error ->
        []
    end
  end

  defp latest_active_historical_workflows(events) when is_list(events) do
    events
    |> Enum.group_by(&backfill_run_id/1)
    |> Enum.flat_map(fn
      {nil, run_events} -> active_workflow_events(run_events)
      {_run_id, run_events} -> run_events |> latest_workflow_event() |> List.wrap()
    end)
    |> Enum.filter(&active_historical_workflow_event?/1)
    |> Enum.map(&historical_workflow_badge_context/1)
  end

  defp active_workflow_events(events) do
    Enum.filter(events, &active_historical_workflow_event?/1)
  end

  defp latest_workflow_event(events) do
    events
    |> Enum.sort_by(&{event_occurred_at_us(&1), event_id(&1)}, :desc)
    |> List.first()
  end

  defp active_historical_workflow_event?(event) do
    event_type(event) in @active_backfill_lifecycle_event_types and
      event_type(event) not in @terminal_backfill_lifecycle_event_types
  end

  defp terminal_historical_workflow_outcomes(events) when is_list(events) do
    events
    |> Enum.group_by(&backfill_run_id/1)
    |> Enum.flat_map(fn
      {nil, run_events} -> terminal_workflow_events(run_events)
      {_run_id, run_events} -> run_events |> latest_workflow_event() |> List.wrap()
    end)
    |> Enum.filter(&terminal_historical_workflow_event?/1)
    |> Enum.map(&historical_workflow_badge_context/1)
  end

  defp terminal_workflow_events(events) do
    Enum.filter(events, &terminal_historical_workflow_event?/1)
  end

  defp terminal_historical_workflow_event?(event) do
    event_type(event) in @terminal_backfill_lifecycle_event_types
  end

  defp put_frame_active_historical_workflows(%Frame{} = frame, workflows) do
    frame_workflows =
      workflows
      |> Enum.filter(&historical_workflow_matches_frame?(&1, frame))
      |> Enum.uniq_by(&{Map.get(&1, :source_record_id), Map.get(&1, :run_id), Map.get(&1, :kind)})

    case frame_workflows do
      [] ->
        frame

      [_workflow | _rest] ->
        evidence =
          frame_workflows
          |> Enum.map(&historical_workflow_evidence_event/1)
          |> DataLinks.telemetry_backfill_lifecycle_event_evidence_refs()

        meta =
          frame.meta
          |> Map.put(:active_historical_workflows, frame_workflows)
          |> merge_frame_evidence(evidence)

        %Frame{frame | meta: meta}
    end
  end

  defp put_frame_historical_workflow_outcomes(%Frame{} = frame, outcomes) do
    frame_outcomes =
      outcomes
      |> Enum.filter(&historical_workflow_matches_frame?(&1, frame))
      |> Enum.uniq_by(&{Map.get(&1, :source_record_id), Map.get(&1, :run_id), Map.get(&1, :kind)})

    case frame_outcomes do
      [] ->
        frame

      [_outcome | _rest] ->
        evidence =
          frame_outcomes
          |> Enum.map(&historical_workflow_evidence_event/1)
          |> DataLinks.telemetry_backfill_lifecycle_event_evidence_refs()

        meta =
          frame.meta
          |> Map.put(:historical_workflow_outcomes, frame_outcomes)
          |> merge_frame_evidence(evidence)

        %Frame{frame | meta: meta}
    end
  end

  defp historical_workflow_matches_frame?(workflow, %Frame{} = frame) do
    workflow_point = Map.get(workflow, :point_id) || Map.get(workflow, :observable_id)
    frame_point = frame.meta[:point_id] || frame.meta[:observable_id]

    workflow_point in [nil, ""] or workflow_point == frame_point
  end

  defp historical_workflow_badge_context(event) do
    %{
      category: :telemetry_backfill,
      kind: event_type(event),
      source_record_id: event_id(event),
      run_id: backfill_run_id(event),
      point_id: event_point_id(event),
      observable_id: event_observable_id(event),
      occurred_at: event_occurred_at(event)
    }
  end

  defp historical_workflow_evidence_event(workflow) do
    %{
      backfill_lifecycle_event_id: Map.get(workflow, :source_record_id),
      occurred_at: Map.get(workflow, :occurred_at)
    }
  end

  defp merge_frame_evidence(meta, []), do: meta

  defp merge_frame_evidence(meta, evidence) when is_map(meta) and is_list(evidence) do
    Map.put(
      meta,
      :evidence,
      (List.wrap(Map.get(meta, :evidence)) ++ evidence)
      |> Enum.uniq_by(&evidence_ref_identity/1)
    )
  end

  defp event_type(event), do: event_value(event, :event_type)
  defp backfill_run_id(event), do: event_value(event, :backfill_run_id)
  defp event_id(event), do: event_value(event, :backfill_lifecycle_event_id)
  defp event_point_id(event), do: event_value(event, :point_id)
  defp event_observable_id(event), do: event_value(event, :observable_id)
  defp event_occurred_at(event), do: event_value(event, :occurred_at)

  defp event_occurred_at_us(event) do
    case event_value(event, :occurred_at) do
      %DateTime{} = occurred_at -> DateTime.to_unix(occurred_at, :microsecond)
      _missing -> 0
    end
  end

  defp event_value(event, key) when is_map(event) and is_atom(key) do
    Map.get(event, key, Map.get(event, Atom.to_string(key)))
  end

  defp event_value(_event, _key), do: nil

  defp evidence_ref_identity(%{kind: kind, id: id}), do: {kind, id}
  defp evidence_ref_identity(ref), do: ref

  defp identity_state_opts(
         %PlannedSourceRequest{} = request,
         source_binding,
         organization_id,
         mission_id
       ) do
    [
      organization_id: organization_id,
      mission_id: mission_id,
      realm: realm(request, source_binding),
      replay_run_id: replay_run_id(request),
      data_source_id: data_source_id(request, source_binding),
      binding_id: source_binding_id(source_binding)
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
  end

  defp put_revision_summary(%Frame{} = frame, %{identity_count: 0}), do: frame

  defp put_revision_summary(%Frame{} = frame, summary) do
    warning_codes =
      frame.meta
      |> Map.get(:warning_codes, [])
      |> Kernel.++(summary.warning_codes)
      |> Enum.uniq()

    %Frame{
      frame
      | meta:
          frame.meta
          |> Map.put(:revision_state, summary)
          |> Map.put(:telemetry_revision_dependency, summary.dependency)
          |> merge_frame_evidence(Map.get(summary, :evidence, []))
          |> Map.put(:warning_codes, warning_codes)
    }
  end

  defp telemetry_revision_dependency(frames) do
    dependencies =
      frames
      |> Enum.map(fn
        %Frame{meta: %{telemetry_revision_dependency: dependency}} when is_map(dependency) ->
          dependency

        _frame ->
          nil
      end)
      |> Enum.reject(&is_nil/1)

    case dependencies do
      [] ->
        nil

      [dependency] ->
        dependency

      dependencies ->
        %{
          kind: :telemetry_observation_identity_state_set,
          fingerprint:
            "telemetry-revision-set:" <>
              RuntimeCacheKey.fingerprint(dependencies),
          dependencies: dependencies
        }
    end
  end

  defp revision_warnings(_request, _frame, %{identity_count: 0}), do: []

  defp revision_warnings(%PlannedSourceRequest{} = request, %Frame{} = frame, summary) do
    Enum.map(summary.warning_codes, fn code ->
      %ResolveWarning{
        code: code,
        severity: :warning,
        scope: :frame,
        frame_id: frame.frame_id,
        message: revision_warning_message(code),
        details:
          summary
          |> Map.drop([:warning_codes])
          |> Map.merge(%{
            source_request_id: request.request_id,
            observable_id: frame.meta[:observable_id],
            point_id: frame.meta[:point_id]
          })
          |> put_telemetry_warning_actions(request, frame.meta[:observable_id]),
        links: DataLinks.request_observable_links(request, source: :warning)
      }
    end)
  end

  defp warning_key(%ResolveWarning{} = warning) do
    {warning.code, warning.scope, warning.frame_id, warning.field_name}
  end

  defp revision_warning_message(:conflicting_observations),
    do: "Telemetry range contains unresolved observation conflicts"

  defp revision_warning_message(:corrected_range),
    do: "Telemetry range contains corrected observations"

  defp revision_warning_message(:advisory_backfill),
    do: "Telemetry range contains advisory or backfilled observations"

  defp revision_warning_message(:mixed_revisions),
    do: "Telemetry range contains multiple observation revision states"

  defp revision_warning_message(code), do: "Telemetry range contains #{code}"

  defp sample_identity_ids(%Sample{} = sample) do
    [
      storage_value(sample.provenance, :observation_identity_id),
      metadata_value(sample.provenance, :observation_identity_id)
    ]
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.uniq()
  end

  defp storage_value(provenance, key) when is_map(provenance) do
    provenance
    |> metadata_value(:storage)
    |> metadata_value(key)
  end

  defp storage_value(_provenance, _key), do: nil

  defp latest_time_axis(%Sample{generation_time: %DateTime{}}), do: :generation_time
  defp latest_time_axis(_sample), do: :receipt_time

  defp sample_time(%Sample{generation_time: %DateTime{} = generation_time}), do: generation_time
  defp sample_time(%Sample{receipt_time: receipt_time}), do: receipt_time

  defp sample_time(%Sample{receipt_time: %DateTime{} = receipt_time}, :receipt_time),
    do: receipt_time

  defp sample_time(%Sample{} = sample, :generation_time), do: sample_time(sample)
  defp sample_time(%Sample{} = sample, _axis), do: sample_time(sample)

  defp bounded_history_frame_axis(%PlannedSourceRequest{} = request, source_filter_context) do
    case context_value(source_filter_context, :time_axis) || time_axis(request) do
      :generation_time -> :generation_time
      "generation_time" -> :generation_time
      _axis -> :receipt_time
    end
  end

  defp watermark(
         %PlannedSourceRequest{} = request,
         source_binding,
         organization_id,
         mission_id,
         opts
       ) do
    if watermarks_supported?(source_binding) do
      watermark_fun = Keyword.get(opts, :watermark_fun, &default_watermark/4)
      watermark_opts = watermark_opts(request, source_binding, opts)

      request.observables
      |> Enum.map(fn observable_id ->
        {observable_id,
         watermark_fun.(organization_id, mission_id, observable_id, watermark_opts)}
      end)
      |> request_watermark(request, source_binding)
    else
      unknown_watermark(request, source_binding)
    end
  end

  defp unknown_watermark(%PlannedSourceRequest{} = request, source_binding) do
    %SourceWatermark{
      logical_source: :telemetry,
      request_id: request.request_id,
      source_binding_id: source_binding_id(source_binding),
      realm: realm(request, source_binding),
      replay_run_id: replay_run_id(request),
      data_source_id: data_source_id(request, source_binding),
      dataset: dataset(source_binding),
      scope: request.scope_context,
      confidence: :unknown
    }
  end

  defp request_watermark(point_results, %PlannedSourceRequest{} = request, source_binding) do
    normalized_results =
      Enum.map(point_results, fn {observable_id, result} ->
        {observable_id, normalize_watermark_result(result)}
      end)

    point_watermarks =
      Map.new(normalized_results, fn {observable_id, result} ->
        {observable_id, result}
      end)

    if Enum.all?(normalized_results, fn {_observable_id, result} ->
         Map.get(result, :confidence) in [:authoritative, :best_effort]
       end) do
      %SourceWatermark{
        logical_source: :telemetry,
        request_id: request.request_id,
        source_binding_id: source_binding_id(source_binding),
        realm: realm(request, source_binding),
        replay_run_id: replay_run_id(request),
        data_source_id: data_source_id(request, source_binding),
        dataset: dataset(source_binding),
        scope: request.scope_context,
        complete_through: minimum_datetime(normalized_results, :complete_through),
        latest_receipt_time: maximum_datetime(normalized_results, :latest_receipt_time),
        retention_starts_at: minimum_datetime(normalized_results, :retention_starts_at),
        confidence: :best_effort,
        meta:
          source_watermark_meta(%{
            point_watermarks: point_watermarks,
            canonical_mode: :physical,
            aggregate_semantics: :physical_as_recorded
          })
      }
    else
      %SourceWatermark{
        unknown_watermark(request, source_binding)
        | meta:
            source_watermark_meta(%{
              point_watermarks: point_watermarks,
              canonical_mode: :physical,
              aggregate_semantics: :physical_as_recorded
            })
      }
    end
  end

  defp source_watermark_meta(meta), do: meta

  defp normalize_watermark_result({:ok, result}) when is_map(result), do: result

  defp normalize_watermark_result({:error, reason}) do
    %{confidence: :unknown, error: inspect(reason)}
  end

  defp normalize_watermark_result(result) when is_map(result), do: result
  defp normalize_watermark_result(other), do: %{confidence: :unknown, error: inspect(other)}

  defp minimum_datetime(normalized_results, key) do
    normalized_results
    |> Enum.map(fn {_observable_id, result} -> Map.get(result, key) end)
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(nil, &earlier_datetime/2)
  end

  defp maximum_datetime(normalized_results, key) do
    normalized_results
    |> Enum.map(fn {_observable_id, result} -> Map.get(result, key) end)
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(nil, &later_datetime/2)
  end

  defp earlier_datetime(datetime, nil), do: datetime
  defp earlier_datetime(datetime, minimum), do: compare_datetime(datetime, minimum, :lt)

  defp later_datetime(datetime, nil), do: datetime
  defp later_datetime(datetime, maximum), do: compare_datetime(datetime, maximum, :gt)

  defp compare_datetime(datetime, other, comparison) do
    if DateTime.compare(datetime, other) == comparison, do: datetime, else: other
  end

  defp watermark_opts(%PlannedSourceRequest{} = request, source_binding, opts) do
    {from_receipt_time, to_receipt_time, _warnings} = receipt_time_bounds(request)

    [
      realm: realm(request, source_binding),
      data_source_id: data_source_id(request, source_binding),
      source_binding_id: source_binding_id(source_binding),
      dataset: dataset(source_binding),
      replay_run_id: replay_run_id(request),
      spacecraft_id: spacecraft_id(request.scope_context),
      source_endpoint_ids: source_endpoint_ids(request, opts),
      from_receipt_time: from_receipt_time,
      to_receipt_time: to_receipt_time
    ]
    |> Kernel.++(selection_policy_opts(request))
    |> Kernel.++(connection_opts(opts))
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
  end

  defp watermarks_supported?(%{data_source: %{capabilities: capabilities}})
       when is_map(capabilities) do
    Map.get(capabilities, :watermarks?, Map.get(capabilities, "watermarks?")) == true
  end

  defp watermarks_supported?(_source_binding), do: false

  defp source_binding_id(%{binding: %{binding_id: binding_id}}), do: binding_id
  defp source_binding_id(_source_binding), do: nil

  defp data_source_id(_request, %{data_source: %{data_source_id: data_source_id}}),
    do: data_source_id

  defp data_source_id(request, _source_binding),
    do: context_value(request.data_context, :data_source_id)

  defp dataset(%{dataset: dataset}), do: dataset
  defp dataset(_source_binding), do: nil

  defp realm(_request, %{realm: realm}), do: realm
  defp realm(request, _source_binding), do: context_value(request.data_context, :realm) || :flight

  defp replay_run_id(%PlannedSourceRequest{} = request) do
    DataContext.source_value(request.data_context, request.logical_source, :replay_run_id) ||
      context_value(request.time_context, :replay_run_id)
  end

  defp source_endpoint_ids(%PlannedSourceRequest{} = request, opts) do
    request.scope_context
    |> direct_source_endpoint_ids()
    |> Kernel.++(contact_source_endpoint_ids(request, opts))
    |> normalize_source_endpoint_ids()
  end

  defp direct_source_endpoint_ids(scope_context) do
    primary_ids =
      if ScopeContext.primary_kind(scope_context) in [:source_endpoint, "source_endpoint"] do
        ScopeContext.primary_ids(scope_context)
      else
        []
      end

    typed_id =
      scope_context
      |> ScopeContext.scope_id(:source_endpoint)
      |> List.wrap()

    primary_ids ++ typed_id
  end

  defp contact_source_endpoint_ids(%PlannedSourceRequest{} = request, opts) do
    request.scope_context
    |> ScopeContext.scope_ids(:contact)
    |> Enum.flat_map(fn contact_id ->
      organization_id = request.organization_id
      mission_id = request.mission_id

      fetch_contact_source_endpoint_ids(organization_id, mission_id, contact_id, opts)
    end)
  end

  defp fetch_contact_source_endpoint_ids(organization_id, mission_id, contact_id, opts) do
    case fetch_scheduled_contact(organization_id, mission_id, contact_id, opts) do
      {:ok, contact} ->
        contact_source_endpoint_refs(contact)

      {:error, :scheduled_contact_not_found} ->
        case fetch_realized_contact(organization_id, mission_id, contact_id, opts) do
          {:ok, contact} -> contact_source_endpoint_refs(contact)
          {:error, _reason} -> []
        end

      {:error, _reason} ->
        []
    end
  end

  defp fetch_scheduled_contact(organization_id, mission_id, contact_id, opts) do
    fetch_scheduled_contact =
      Keyword.get(opts, :fetch_scheduled_contact, &Cadence.fetch_scheduled_contact/3)

    fetch_scheduled_contact.(organization_id, mission_id, contact_id)
  end

  defp fetch_realized_contact(organization_id, mission_id, contact_id, opts) do
    fetch_realized_contact =
      Keyword.get(opts, :fetch_realized_contact, &Cadence.fetch_realized_contact/3)

    fetch_realized_contact.(organization_id, mission_id, contact_id)
  end

  defp contact_source_endpoint_refs(contact) when is_map(contact) do
    contact
    |> context_value(:source_endpoint_refs)
    |> normalize_source_endpoint_ids()
  end

  defp contact_source_endpoint_refs(_contact), do: []

  defp normalize_source_endpoint_ids(ids) when is_list(ids) do
    ids
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.uniq()
  end

  defp normalize_source_endpoint_ids(id) when is_binary(id) and id != "", do: [id]
  defp normalize_source_endpoint_ids(_ids), do: []

  defp default_decimated_history(nil, _mission_id, _point_id, _opts) do
    {:error, :missing_tenant_context}
  end

  defp default_decimated_history(organization_id, mission_id, point_id, opts) do
    case Cadence.decimated_telemetry_history_result(organization_id, mission_id, point_id, opts) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp default_history(nil, mission_id, point_id, opts) do
    Cadence.telemetry_history_result(mission_id, point_id, opts)
  end

  defp default_history(organization_id, mission_id, point_id, opts) do
    Cadence.telemetry_history_result(organization_id, mission_id, point_id, opts)
  end

  defp default_watermark(nil, _mission_id, _point_id, _opts) do
    {:error, :missing_tenant_context}
  end

  defp default_watermark(organization_id, mission_id, point_id, opts) do
    Cadence.telemetry_watermark(organization_id, mission_id, point_id, opts)
  end

  defp default_latest(nil, mission_id, point_id, opts) do
    Cadence.latest_telemetry_value(mission_id, point_id, opts)
  end

  defp default_latest(organization_id, mission_id, point_id, opts) do
    Cadence.latest_telemetry_value(organization_id, mission_id, point_id, opts)
  end

  defp warning(%PlannedSourceRequest{} = request, code, severity, message, details) do
    %ResolveWarning{
      code: code,
      severity: severity,
      scope: :dashboard,
      message: message,
      details:
        details
        |> Map.put(:source_request_id, request.request_id)
        |> put_telemetry_warning_actions(request, warning_observable_id(request, details)),
      links: DataLinks.request_observable_links(request, source: :warning)
    }
  end

  defp put_telemetry_warning_actions(details, %PlannedSourceRequest{} = request, observable_id) do
    actions =
      TelemetryActions.explore_actions(request, observable_id, [],
        source: :warning,
        action_id: "telemetry-warning-explore:#{request.request_id}:#{observable_id || "unknown"}"
      )

    existing_actions = List.wrap(Map.get(details, :actions))

    if existing_actions == [] and actions == [] do
      details
    else
      Map.put(details, :actions, merge_warning_actions(existing_actions, actions))
    end
  end

  defp merge_warning_actions(existing_actions, new_actions) do
    existing_actions
    |> Kernel.++(new_actions)
    |> Enum.uniq_by(fn
      %{action_id: action_id} when is_binary(action_id) -> action_id
      %{target: target, query: query} -> {target, query}
      action -> action
    end)
  end

  defp warning_observable_id(%PlannedSourceRequest{} = request, details) do
    details[:observable_id] || details["observable_id"] || details[:point_id] ||
      details["point_id"] ||
      List.first(List.wrap(request.observables))
  end

  defp degraded?(warnings) do
    Enum.any?(warnings, &(&1.severity != :info))
  end

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)

  defp supported_capability(%PlannedSourceRequest{} = request) do
    case sampling_mode(request) do
      :latest -> :latest_value
      :decimated_envelope -> :native_decimated_envelope
      _other -> bounded_history_capability(request)
    end
  end

  defp bounded_history_capability(%PlannedSourceRequest{} = request) do
    case time_axis(request) do
      :generation_time -> :bounded_generation_time_history
      _axis -> :bounded_receipt_time_history
    end
  end

  defp sampling_mode(%PlannedSourceRequest{sampling: sampling}) do
    sampling
    |> context_value(:mode)
    |> normalize_atom()
  end

  defp time_axis(%PlannedSourceRequest{time_context: time_context}) do
    time_context
    |> context_value(:axis)
    |> normalize_atom()
  end

  defp time_mode(%PlannedSourceRequest{time_context: time_context}) do
    time_context
    |> context_value(:mode)
    |> normalize_atom()
  end

  defp time_range_requested?(time_context) do
    mode = time_context |> context_value(:mode) |> normalize_atom()

    mode in [:archive, :range] or
      not is_nil(first_context_value(time_context, [:from, :start, :start_time])) or
      not is_nil(first_context_value(time_context, [:to, :end, :end_time]))
  end

  defp value_type(%PlannedSourceRequest{value_type: value_type}) do
    case normalize_atom(value_type) do
      :raw -> :raw
      _other -> :engineering
    end
  end

  defp raw_point_limit(%PlannedSourceRequest{sampling: sampling}) do
    case context_value(sampling, :max_raw_points) || context_value(sampling, :limit) do
      limit when is_integer(limit) and limit > 0 -> min(limit, @default_limit)
      _other -> @default_limit
    end
  end

  defp target_points(%PlannedSourceRequest{sampling: sampling}) do
    case context_value(sampling, :target_points) do
      target when is_integer(target) and target > 0 -> target
      _other -> nil
    end
  end

  defp bucket_width_ms(%PlannedSourceRequest{sampling: sampling}) do
    case context_value(sampling, :bucket_width_ms) do
      width when is_integer(width) and width > 0 -> width
      _other -> nil
    end
  end

  defp spacecraft_id(scope_context) do
    ScopeContext.scope_id(scope_context, :spacecraft)
  end

  defp sample_value(%Sample{} = sample, :raw), do: sample.raw_value
  defp sample_value(%Sample{} = sample, :engineering), do: sample.engineering_value

  defp bucket_representative_value(bucket) do
    bucket_value(bucket, :value) || bucket_value(bucket, :mean)
  end

  defp bucket_value(bucket, :bucket_start) do
    first_context_value(bucket, [:bucket_start, :start, :from])
  end

  defp bucket_value(bucket, :bucket_end) do
    first_context_value(bucket, [:bucket_end, :end, :to])
  end

  defp bucket_value(bucket, key), do: context_value(bucket, key)

  defp field_kind(values) do
    values
    |> Enum.reject(&is_nil/1)
    |> List.first()
    |> value_kind()
  end

  defp value_kind(value) when is_number(value), do: :number
  defp value_kind(value) when is_boolean(value), do: :boolean
  defp value_kind(value) when is_atom(value), do: :enum
  defp value_kind(_value), do: :string

  defp first_context_value(context, keys) do
    keys
    |> Enum.find_value(&context_value(context, &1))
  end

  defp context_value(context, key) when is_map(context) and is_atom(key) do
    with :error <- Map.fetch(context, key),
         :error <- Map.fetch(context, Atom.to_string(key)) do
      nil
    else
      {:ok, value} -> value
    end
  end

  defp context_value(_context, _key), do: nil

  defp maybe_put_context(context, _key, value) when value in [nil, "", []], do: context
  defp maybe_put_context(context, key, value), do: Map.put(context, key, value)

  defp native_decimation?(%{data_source: %{capabilities: capabilities}}) do
    capability_value(capabilities, :native_decimation?) == true
  end

  defp native_decimation?(_source_binding), do: false

  defp capability_value(capabilities, key) when is_map(capabilities) and is_atom(key) do
    Map.get(capabilities, key, Map.get(capabilities, Atom.to_string(key)))
  end

  defp capability_value(_capabilities, _key), do: nil

  defp normalize_atom(value) when is_atom(value), do: value

  defp normalize_atom(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> String.replace("-", "_")
    |> String.to_existing_atom()
  rescue
    ArgumentError -> value
  end

  defp normalize_atom(value), do: value
end
