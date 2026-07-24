defmodule Cadence.Dashboards.DataSourceRegistry do
  @moduledoc """
  In-memory dashboard data-source and binding resolver.

  This is the v0 seam before persisted source bindings exist. Callers may pass
  `:data_sources` and `:data_bindings` opts to override or augment defaults.
  """

  alias Cadence.Dashboards.{
    DataBinding,
    DataContext,
    DataLinks,
    DataSource,
    DefaultSourceAdapters,
    PlannedSourceRequest,
    ResolvedSourceBinding,
    ResolveWarning,
    SourceActions,
    SourceFacts,
    SourceHealth,
    SourceHealthEvent,
    SourceHealthStatus,
    SourceReadiness,
    TelemetryActions
  }

  alias Cadence.Dashboards.DataSourceRegistry.Facts
  alias Cadence.Dashboards.DataSourceRegistry.HistoricalResolver
  alias Cadence.Management.DataSources

  @spec resolve(PlannedSourceRequest.t(), keyword()) ::
          {:ok, ResolvedSourceBinding.t()} | {:error, ResolveWarning.t()}
  def resolve(%PlannedSourceRequest{} = request, opts \\ []) when is_list(opts) do
    with :ok <- validate_replay_request(request) do
      do_resolve(request, opts)
    end
  end

  @spec resolve_segments(PlannedSourceRequest.t(), keyword()) ::
          {:ok, [ResolvedSourceBinding.t()]} | {:error, ResolveWarning.t()}
  def resolve_segments(%PlannedSourceRequest{} = request, opts \\ []) when is_list(opts) do
    with :ok <- validate_replay_request(request) do
      do_resolve_segments(request, opts)
    end
  end

  @spec facts(PlannedSourceRequest.t(), keyword()) ::
          {:ok, SourceFacts.t()} | {:error, ResolveWarning.t()}
  def facts(%PlannedSourceRequest{} = request, opts \\ []) when is_list(opts) do
    Facts.fetch(request, opts, &resolve/2, &warning/5)
  end

  defp do_resolve(%PlannedSourceRequest{} = request, opts) do
    case registry_data(request, opts) do
      {:historical, data_sources, intervals} ->
        HistoricalResolver.resolve(request, data_sources, intervals, opts)

      {:current, data_sources, data_bindings, source_health_statuses} ->
        resolve_current(request, data_sources, data_bindings, source_health_statuses, opts)
    end
  end

  defp do_resolve_segments(%PlannedSourceRequest{} = request, opts) do
    case registry_data(request, opts) do
      {:historical, data_sources, intervals} ->
        HistoricalResolver.resolve_segments(request, data_sources, intervals, opts)

      {:current, data_sources, data_bindings, source_health_statuses} ->
        resolve_current_segment(
          request,
          data_sources,
          data_bindings,
          source_health_statuses,
          opts
        )
    end
  end

  defp resolve_current_segment(request, data_sources, data_bindings, source_health_statuses, opts) do
    with {:ok, resolved_binding} <-
           resolve_current(request, data_sources, data_bindings, source_health_statuses, opts) do
      {:ok, [resolved_binding]}
    end
  end

  defp registry_data(%PlannedSourceRequest{} = request, opts) do
    cond do
      Keyword.has_key?(opts, :data_sources) or Keyword.has_key?(opts, :data_bindings) ->
        {:current, Keyword.get(opts, :data_sources, default_data_sources()),
         Keyword.get(opts, :data_bindings, default_data_bindings()),
         Keyword.get(opts, :source_health_statuses, [])}

      persisted?(opts) and source_binding_at(opts) ->
        persisted_registry_data_at(request, opts)

      persisted?(opts) ->
        persisted_registry_data(request)

      true ->
        {:current, default_data_sources(), default_data_bindings(), []}
    end
  end

  defp validate_replay_request(%PlannedSourceRequest{} = request) do
    if replay_request?(request) do
      cond do
        not present?(requested_replay_run_id(request)) ->
          {:error,
           warning(
             request,
             :missing_replay_run_id,
             :error,
             "Replay source requests require a replay run id",
             %{
               organization_id: request.organization_id,
               mission_id: request.mission_id,
               logical_source: request.logical_source,
               realm: requested_realm(request),
               requested_time_mode: :replay_run
             }
           )}

        normalize_realm(requested_realm(request)) != "replay" ->
          {:error,
           warning(
             request,
             :replay_source_required,
             :error,
             "Replay source requests require a replay realm",
             %{
               organization_id: request.organization_id,
               mission_id: request.mission_id,
               logical_source: request.logical_source,
               realm: requested_realm(request),
               requested_time_mode: :replay_run,
               replay_run_id: requested_replay_run_id(request)
             }
           )}

        true ->
          :ok
      end
    else
      :ok
    end
  end

  defp persisted_registry_data(%PlannedSourceRequest{} = request) do
    data_sources = DataSources.list_data_sources(request.organization_id, request.mission_id)
    data_bindings = DataSources.list_data_bindings(request.organization_id, request.mission_id)

    if data_sources == [] and data_bindings == [] do
      {:current, default_data_sources(), default_data_bindings(), []}
    else
      {data_sources, data_bindings} =
        augment_registry_defaults(data_sources, data_bindings)

      source_health_statuses =
        SourceHealth.list_source_health_statuses(request.organization_id, request.mission_id,
          logical_source: request.logical_source,
          source_health_keys: source_health_keys_for_request(request, data_bindings, data_sources)
        )

      {:current, data_sources, data_bindings, source_health_statuses}
    end
  end

  defp augment_registry_defaults(data_sources, data_bindings) do
    configured_logical_sources =
      data_bindings
      |> Enum.map(& &1.logical_source)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    missing_bindings =
      default_data_bindings()
      |> Enum.reject(&MapSet.member?(configured_logical_sources, &1.logical_source))

    missing_data_source_ids =
      missing_bindings
      |> Enum.map(& &1.data_source_id)
      |> MapSet.new()

    missing_data_sources =
      default_data_sources()
      |> Enum.filter(&MapSet.member?(missing_data_source_ids, &1.data_source_id))

    {
      Enum.uniq_by(data_sources ++ missing_data_sources, & &1.data_source_id),
      Enum.uniq_by(data_bindings ++ missing_bindings, & &1.binding_id)
    }
  end

  defp persisted_registry_data_at(%PlannedSourceRequest{} = request, _opts) do
    data_sources = DataSources.list_data_sources(request.organization_id, request.mission_id)

    intervals =
      DataSources.list_data_binding_intervals(request.organization_id, request.mission_id,
        logical_source: request.logical_source,
        realm: requested_realm(request)
      )

    if data_sources == [] and intervals == [] do
      {:current, default_data_sources(), default_data_bindings(), []}
    else
      {:historical, data_sources, intervals}
    end
  end

  defp default_data_sources,
    do: [
      DataSources.default_managed_data_source(),
      DataSources.default_limits_data_source(),
      DataSources.default_operational_observables_data_source(),
      DataSources.default_events_data_source()
    ]

  defp default_data_bindings,
    do: [
      DataSources.default_flight_telemetry_binding(),
      DataSources.default_flight_limits_binding(),
      DataSources.default_flight_operational_observables_binding(),
      DataSources.default_flight_events_binding()
    ]

  defp persisted?(opts) do
    Keyword.get_lazy(opts, :persisted?, fn ->
      :cadence
      |> Application.get_env(:dashboard_data_sources, [])
      |> Keyword.get(:persisted?, false)
    end)
  end

  defp resolve_current(
         %PlannedSourceRequest{} = request,
         data_sources,
         data_bindings,
         source_health_statuses,
         opts
       ) do
    with {:ok, binding, selection} <-
           select_binding(request, data_sources, data_bindings, source_health_statuses, opts),
         {:ok, data_source} <- fetch_data_source(binding, data_sources, request, selection) do
      {:ok,
       %ResolvedSourceBinding{
         binding: binding,
         data_source: data_source,
         realm: binding.realm,
         dataset: binding.dataset,
         source_selection:
           selection
           |> put_selected_binding(binding)
           |> put_selected_data_source(data_source)
           |> put_selection_strategy(:current_binding)
       }}
    end
  end

  defp select_binding(
         %PlannedSourceRequest{} = request,
         data_sources,
         bindings,
         source_health_statuses,
         opts
       ) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    readiness_policy = SourceReadiness.policy(opts)

    selection =
      current_source_selection(
        request,
        bindings,
        data_sources,
        source_health_statuses,
        readiness_policy,
        now,
        opts
      )

    matching_bindings =
      bindings
      |> Enum.filter(
        &(binding_matches?(&1, request) and binding_active?(&1, now) and
            binding_source_ready?(
              &1,
              data_sources,
              request,
              source_health_statuses,
              readiness_policy,
              opts
            ))
      )
      |> Enum.sort_by(&binding_sort_key/1)

    case matching_bindings do
      [binding | _rest] ->
        {:ok, binding, select_candidate(selection, binding.binding_id)}

      [] ->
        no_current_binding_warning(request, selection)
    end
  end

  defp no_current_binding_warning(%PlannedSourceRequest{} = request, selection) do
    case Enum.find(Map.get(selection, :candidates, []), &candidate_source_readiness_blocked?/1) do
      nil ->
        missing_binding_warning(request, selection)

      candidate ->
        {:error,
         warning(
           request,
           source_readiness_warning_code(candidate),
           :error,
           "No ready source binding matches request",
           %{
             organization_id: request.organization_id,
             mission_id: request.mission_id,
             logical_source: request.logical_source,
             realm: requested_realm(request),
             binding_id: Map.get(candidate, :binding_id),
             data_source_id: Map.get(candidate, :data_source_id),
             source_health: Map.get(candidate, :source_health),
             source_health_reason: Map.get(candidate, :source_health_reason),
             source_health_freshness: Map.get(candidate, :source_health_freshness),
             connection_test_result: Map.get(candidate, :connection_test_result),
             connection_test_kind: Map.get(candidate, :connection_test_kind),
             connection_test_message: Map.get(candidate, :connection_test_message),
             source_selection: selection
           }
         )}
    end
  end

  defp missing_binding_warning(%PlannedSourceRequest{} = request, selection) do
    {code, message} =
      if replay_request?(request) do
        {:missing_replay_source_binding, "No replay source binding matches request"}
      else
        {:missing_source_binding, "No source binding matches request"}
      end

    {:error,
     warning(request, code, :error, message, %{
       organization_id: request.organization_id,
       mission_id: request.mission_id,
       logical_source: request.logical_source,
       realm: requested_realm(request),
       source_selection: selection
     })}
  end

  defp candidate_source_readiness_blocked?(candidate) when is_map(candidate) do
    Enum.any?(Map.get(candidate, :reasons, []), &(&1 in SourceReadiness.readiness_reasons()))
  end

  defp candidate_source_readiness_blocked?(_candidate), do: false

  defp source_readiness_warning_code(candidate) do
    reasons = Map.get(candidate, :reasons, [])

    cond do
      :source_degraded in reasons -> :source_degraded
      :connection_test_failed in reasons -> :source_connection_failed
      :connection_test_blocked in reasons -> :source_connection_failed
      true -> :source_unavailable
    end
  end

  defp fetch_data_source(
         %DataBinding{} = binding,
         data_sources,
         %PlannedSourceRequest{} = request,
         selection
       ) do
    case Enum.find(data_sources, &(&1.data_source_id == binding.data_source_id)) do
      %DataSource{} = data_source ->
        validate_data_source(data_source, binding, request, selection)

      nil ->
        {:error,
         warning(
           request,
           :missing_data_source,
           :error,
           "Source binding references unknown data source",
           %{
             binding_id: binding.binding_id,
             data_source_id: binding.data_source_id,
             source_selection: selection
           }
         )}
    end
  end

  defp validate_data_source(
         %DataSource{} = data_source,
         %DataBinding{} = binding,
         %PlannedSourceRequest{} = request,
         selection
       ) do
    with :ok <- validate_data_source_active(data_source, binding, request, selection),
         :ok <- validate_data_source_configuration(data_source, binding, request, selection) do
      {:ok, DefaultSourceAdapters.materialize(data_source, binding.logical_source)}
    end
  end

  defp validate_data_source_active(
         %DataSource{} = data_source,
         %DataBinding{} = binding,
         %PlannedSourceRequest{} = request,
         selection
       ) do
    if DataSource.active?(data_source) do
      :ok
    else
      {:error,
       warning(
         request,
         :disabled_data_source,
         :error,
         "Source binding resolved to a disabled data source",
         %{
           binding_id: binding.binding_id,
           data_source_id: data_source.data_source_id,
           source_status: data_source.status,
           disabled_at: data_source.disabled_at,
           source_selection: selection |> put_selected_data_source(data_source)
         }
       )}
    end
  end

  defp validate_data_source_configuration(
         %DataSource{} = data_source,
         %DataBinding{} = binding,
         %PlannedSourceRequest{} = request,
         selection
       ) do
    case DataSource.validate_configuration(data_source) do
      :ok ->
        :ok

      {:error, errors} ->
        {:error,
         warning(
           request,
           :invalid_data_source_configuration,
           :error,
           "Source binding resolved to an invalid data source configuration",
           %{
             binding_id: binding.binding_id,
             data_source_id: data_source.data_source_id,
             errors:
               Enum.map(errors, fn {field, message} -> %{field: field, message: message} end),
             source_selection: selection |> put_selected_data_source(data_source)
           }
         )}
    end
  end

  defp current_source_selection(
         %PlannedSourceRequest{} = request,
         bindings,
         data_sources,
         source_health_statuses,
         readiness_policy,
         %DateTime{} = now,
         opts
       ) do
    candidates =
      Enum.map(
        bindings,
        &binding_candidate(
          request,
          &1,
          data_sources,
          source_health_statuses,
          readiness_policy,
          now,
          opts
        )
      )

    %{
      strategy: :current_binding,
      source_readiness_policy: readiness_policy,
      logical_source: request.logical_source,
      requested_realm: requested_realm(request),
      requested_time_mode: requested_time_mode(request),
      requested_time_axis: requested_time_axis(request),
      replay_run_id: requested_replay_run_id(request),
      requested_source_binding_id: source_context_value(request, :source_binding_id),
      requested_data_source_id: source_context_value(request, :data_source_id),
      requested_dataset: source_context_value(request, :dataset),
      candidate_count: length(candidates),
      eligible_candidate_count: Enum.count(candidates, &(&1.reasons == [])),
      candidates: candidates
    }
    |> drop_nil_values()
  end

  defp binding_candidate(
         %PlannedSourceRequest{} = request,
         %DataBinding{} = binding,
         data_sources,
         source_health_statuses,
         readiness_policy,
         now,
         opts
       ) do
    binding_reasons = binding_rejection_reasons(request, binding, now)
    data_source = data_source_for_binding(binding, data_sources)

    readiness =
      source_readiness(
        binding_reasons,
        request,
        binding,
        data_source,
        source_health_statuses,
        readiness_policy,
        opts
      )

    reasons = binding_reasons ++ Map.get(readiness, :reasons, [])

    %{
      binding_id: binding.binding_id,
      data_source_id: binding.data_source_id,
      logical_source: binding.logical_source,
      realm: binding.realm,
      dataset: binding.dataset,
      priority: binding.priority,
      status: binding.status,
      organization_id: binding.organization_id,
      mission_id: binding.mission_id,
      active_from: binding.active_from,
      active_to: binding.active_to,
      decision: if(reasons == [], do: :eligible, else: :rejected),
      reasons: reasons
    }
    |> Map.merge(Map.delete(readiness, :reasons))
    |> drop_nil_values()
  end

  defp binding_rejection_reasons(%PlannedSourceRequest{} = request, %DataBinding{} = binding, now) do
    []
    |> maybe_add_reason(
      binding.logical_source != request.logical_source,
      :logical_source_mismatch
    )
    |> maybe_add_reason(
      not matches_scope?(binding.organization_id, request.organization_id),
      :organization_mismatch
    )
    |> maybe_add_reason(
      not matches_scope?(binding.mission_id, request.mission_id),
      :mission_mismatch
    )
    |> maybe_add_reason(
      normalize_realm(binding.realm) != normalize_realm(requested_realm(request)),
      :realm_mismatch
    )
    |> maybe_add_reason(
      not matches_context_value?(
        binding.binding_id,
        source_context_value(request, :source_binding_id)
      ),
      :source_binding_filter_mismatch
    )
    |> maybe_add_reason(
      not matches_context_value?(
        binding.data_source_id,
        source_context_value(request, :data_source_id)
      ),
      :data_source_filter_mismatch
    )
    |> maybe_add_reason(
      not matches_context_value?(binding.dataset, source_context_value(request, :dataset)),
      :dataset_filter_mismatch
    )
    |> maybe_add_reason(not DataBinding.active?(binding), :binding_not_active)
    |> maybe_add_reason(not active_after?(binding.active_from, now), :binding_not_started)
    |> maybe_add_reason(not active_before?(binding.active_to, now), :binding_expired)
    |> Enum.reverse()
  end

  defp binding_source_ready?(
         %DataBinding{} = binding,
         data_sources,
         %PlannedSourceRequest{} = request,
         source_health_statuses,
         readiness_policy,
         opts
       ) do
    data_source = data_source_for_binding(binding, data_sources)

    readiness =
      source_readiness(
        [],
        request,
        binding,
        data_source,
        source_health_statuses,
        readiness_policy,
        opts
      )

    Enum.all?(Map.get(readiness, :reasons, []), &(&1 not in SourceReadiness.readiness_reasons()))
  end

  defp source_readiness(
         binding_reasons,
         _request,
         _binding,
         _data_source,
         _statuses,
         _policy,
         _opts
       )
       when binding_reasons != [] do
    %{reasons: []}
  end

  defp source_readiness([], _request, _binding, nil, _statuses, _policy, _opts),
    do: %{reasons: []}

  defp source_readiness(
         [],
         %PlannedSourceRequest{} = request,
         %DataBinding{} = binding,
         %DataSource{} = data_source,
         source_health_statuses,
         readiness_policy,
         opts
       ) do
    status = source_health_status_for(source_health_statuses, request, binding, data_source)
    classification = SourceHealth.classify_status(status, data_source, opts)
    readiness = SourceReadiness.classify(classification, readiness_policy)
    status = classification.status

    %{
      reasons: readiness.reasons,
      source_readiness_policy_id: readiness.policy_id,
      source_health_freshness: classification.freshness,
      source_health: classification.source_health,
      source_health_reason: classification.reason,
      source_health_observed_at: classification.observed_at,
      source_health_last_seen_at: classification.last_seen_at,
      source_health_age_ms: classification.age_ms,
      source_health_max_age_ms: classification.max_age_ms,
      raw_source_health: classification.raw_source_health,
      raw_source_health_reason: classification.raw_reason,
      connection_test_result: source_health_payload_value(status, :connection_test_result),
      connection_test_kind: source_health_payload_value(status, :connection_test_kind),
      connection_test_message: source_health_payload_value(status, :connection_test_message)
    }
    |> drop_nil_values()
  end

  defp source_health_status_for(source_health_statuses, request, binding, data_source) do
    exact_key =
      request
      |> source_health_identity(binding, data_source)
      |> SourceHealthEvent.source_health_key()

    source_key =
      request
      |> source_health_identity(binding, data_source)
      |> Map.merge(%{source_binding_id: nil, realm: nil, replay_run_id: nil, dataset: nil})
      |> SourceHealthEvent.source_health_key()

    Enum.find(source_health_statuses, &(status_value(&1, :source_health_key) == exact_key)) ||
      Enum.find(source_health_statuses, &(status_value(&1, :source_health_key) == source_key))
  end

  defp source_health_keys_for_request(
         %PlannedSourceRequest{} = request,
         data_bindings,
         data_sources
       ) do
    data_bindings
    |> Enum.filter(&binding_matches?(&1, request))
    |> Enum.flat_map(fn binding ->
      case data_source_for_binding(binding, data_sources) do
        %DataSource{} = data_source ->
          identity = source_health_identity(request, binding, data_source)

          [
            SourceHealthEvent.source_health_key(identity),
            identity
            |> Map.merge(%{source_binding_id: nil, realm: nil, replay_run_id: nil, dataset: nil})
            |> SourceHealthEvent.source_health_key()
          ]

        nil ->
          []
      end
    end)
    |> Enum.uniq()
  end

  defp source_health_identity(
         %PlannedSourceRequest{} = request,
         %DataBinding{} = binding,
         %DataSource{} = data_source
       ) do
    %{
      organization_id:
        request.organization_id || binding.organization_id || data_source.organization_id,
      mission_id: request.mission_id || binding.mission_id || data_source.mission_id,
      logical_source: request.logical_source || binding.logical_source,
      data_source_id: data_source.data_source_id,
      source_binding_id: binding.binding_id,
      realm: binding.realm,
      replay_run_id: requested_replay_run_id(request),
      dataset: binding.dataset
    }
  end

  defp data_source_for_binding(%DataBinding{} = binding, data_sources) do
    Enum.find(data_sources, &(&1.data_source_id == binding.data_source_id))
  end

  defp status_value(%SourceHealthStatus{} = status, key), do: Map.get(status, key)

  defp status_value(status, key) when is_map(status),
    do: Map.get(status, key, Map.get(status, Atom.to_string(key)))

  defp status_value(_status, _key), do: nil

  defp source_health_payload_value(%{payload: payload}, key) when is_map(payload) do
    Map.get(payload, Atom.to_string(key), Map.get(payload, key))
  end

  defp source_health_payload_value(_status, _key), do: nil

  defp maybe_add_reason(reasons, true, reason), do: [reason | reasons]
  defp maybe_add_reason(reasons, false, _reason), do: reasons

  defp select_candidate(selection, binding_id) when is_map(selection) and is_binary(binding_id) do
    candidates =
      selection
      |> Map.get(:candidates, [])
      |> Enum.map(&select_candidate_decision(&1, binding_id))

    selection
    |> Map.put(:candidates, candidates)
    |> put_selected_binding_id(binding_id)
  end

  defp select_candidate(selection, _binding_id), do: selection

  defp select_candidate_decision(candidate, binding_id) do
    cond do
      Map.get(candidate, :binding_id) == binding_id ->
        %{candidate | decision: :selected}

      Map.get(candidate, :decision) == :eligible ->
        %{candidate | decision: :not_selected, reasons: [:lower_priority]}

      true ->
        candidate
    end
  end

  defp put_selected_binding(selection, %DataBinding{} = binding) do
    selection
    |> put_selected_binding_id(binding.binding_id)
    |> Map.put(:selected_realm, binding.realm)
    |> Map.put(:selected_dataset, binding.dataset)
    |> Map.put(:selected_priority, binding.priority)
    |> drop_nil_values()
  end

  defp put_selected_binding_id(selection, binding_id) do
    selection
    |> Map.put(:selected_source_binding_id, binding_id)
    |> drop_nil_values()
  end

  defp put_selected_data_source(selection, %DataSource{} = data_source) when is_map(selection) do
    selection
    |> Map.put(:selected_data_source_id, data_source.data_source_id)
    |> Map.put(:selected_data_source_kind, data_source.kind)
    |> Map.put(:selected_data_source_owner, data_source.owner)
    |> Map.put(:selected_data_source_status, data_source.status)
    |> drop_nil_values()
  end

  defp put_selected_data_source(selection, _data_source), do: selection

  defp put_selection_strategy(selection, strategy) when is_map(selection) do
    Map.put(selection, :strategy, strategy)
  end

  defp drop_nil_values(map) when is_map(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) end)
  end

  defp binding_matches?(%DataBinding{} = binding, %PlannedSourceRequest{} = request) do
    binding.logical_source == request.logical_source and
      matches_scope?(binding.organization_id, request.organization_id) and
      matches_scope?(binding.mission_id, request.mission_id) and
      normalize_realm(binding.realm) == normalize_realm(requested_realm(request)) and
      matches_context_value?(
        binding.binding_id,
        source_context_value(request, :source_binding_id)
      ) and
      matches_context_value?(
        binding.data_source_id,
        source_context_value(request, :data_source_id)
      ) and
      matches_context_value?(binding.dataset, source_context_value(request, :dataset))
  end

  defp binding_active?(%DataBinding{} = binding, %DateTime{} = now) do
    DataBinding.active?(binding) and active_after?(binding.active_from, now) and
      active_before?(binding.active_to, now)
  end

  defp active_after?(nil, _now), do: true
  defp active_after?(active_from, now), do: DateTime.compare(active_from, now) != :gt

  defp active_before?(nil, _now), do: true
  defp active_before?(active_to, now), do: DateTime.compare(active_to, now) == :gt

  defp matches_scope?(nil, _requested), do: true
  defp matches_scope?(scope, requested), do: scope == requested

  defp matches_context_value?(_actual, nil), do: true
  defp matches_context_value?(_actual, ""), do: true
  defp matches_context_value?(actual, requested), do: actual == requested

  defp binding_sort_key(%DataBinding{} = binding) do
    {
      -scope_specificity(binding.organization_id),
      -scope_specificity(binding.mission_id),
      binding.priority
    }
  end

  defp scope_specificity(nil), do: 0
  defp scope_specificity(_value), do: 1

  defp requested_realm(%PlannedSourceRequest{} = request) do
    case context_value(request.data_context, :realm) do
      nil -> default_requested_realm(request)
      realm -> realm
    end
  end

  defp replay_request?(%PlannedSourceRequest{} = request) do
    requested_time_mode(request) == :replay_run
  end

  defp default_requested_realm(%PlannedSourceRequest{} = request) do
    if requested_time_mode(request) == :replay_run, do: :replay, else: :flight
  end

  defp requested_time_mode(%PlannedSourceRequest{} = request) do
    request.time_context
    |> context_value(:mode)
    |> normalize_known_atom([:live, :archive, :range, :replay_run])
  end

  defp requested_time_axis(%PlannedSourceRequest{} = request) do
    request.time_context
    |> context_value(:axis)
    |> normalize_known_atom([:generation_time, :receipt_time, :occurred_at])
  end

  defp requested_replay_run_id(%PlannedSourceRequest{} = request) do
    source_context_value(request, :replay_run_id) ||
      context_value(request.time_context, :replay_run_id)
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value), do: not is_nil(value)

  defp source_context_value(%PlannedSourceRequest{} = request, key) do
    DataContext.source_value(request.data_context, request.logical_source, key)
  end

  defp source_binding_at(opts) do
    case Keyword.get(opts, :source_binding_at) do
      %DateTime{} = at -> at
      _other -> nil
    end
  end

  defp normalize_realm(realm) when is_atom(realm), do: Atom.to_string(realm)
  defp normalize_realm(realm) when is_binary(realm), do: realm

  defp normalize_known_atom(value, known_values) when is_atom(value) do
    if value in known_values, do: value, else: value
  end

  defp normalize_known_atom(value, known_values) when is_binary(value) do
    normalized =
      value
      |> String.trim()
      |> String.downcase()
      |> String.replace("-", "_")

    Enum.find(known_values, &(Atom.to_string(&1) == normalized)) || value
  end

  defp normalize_known_atom(value, _known_values), do: value

  defp warning(%PlannedSourceRequest{} = request, code, severity, message, details) do
    links = DataLinks.request_observable_links(request, source: :warning)

    %ResolveWarning{
      code: code,
      severity: severity,
      scope: :dashboard,
      message: message,
      details:
        details
        |> Map.put(:source_request_id, request.request_id)
        |> SourceActions.put_source_request_context(request)
        |> SourceActions.put_source_warning_actions()
        |> put_telemetry_warning_actions(links),
      links: links
    }
  end

  defp put_telemetry_warning_actions(details, links) do
    actions =
      links
      |> Enum.map(fn link ->
        TelemetryActions.explore_action_from_data_link(link,
          source: :warning,
          action_id:
            "telemetry-warning-explore:#{Map.get(details, :source_request_id)}:#{link.target_id}"
        )
      end)
      |> Enum.reject(&is_nil/1)

    if actions == [] do
      details
    else
      Map.update(details, :actions, actions, &(List.wrap(&1) ++ actions))
    end
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
end
