defmodule Cadence.Dashboards.DataSourceRegistry.HistoricalResolver do
  @moduledoc false

  alias Cadence.Dashboards.{
    DataContext,
    DataLinks,
    PlannedSourceRequest,
    ResolvedSourceBinding,
    ResolveWarning,
    SourceActions,
    TelemetryActions
  }

  alias Cadence.DataSources.AdapterRegistry

  alias Cadence.DataSources.{DataBinding, DataBindingInterval, DataSource}

  def resolve(
        %PlannedSourceRequest{} = request,
        data_sources,
        intervals,
        opts
      ) do
    at = source_binding_at(opts)

    with :ok <- validate_source_binding_range(request, intervals, opts),
         {:ok, interval, selection} <- select_interval(request, intervals, at),
         binding = DataBindingInterval.to_binding(interval),
         {:ok, data_source} <- fetch_data_source(binding, data_sources, request, selection) do
      {:ok,
       %ResolvedSourceBinding{
         binding: binding,
         binding_interval: interval,
         data_source: data_source,
         realm: binding.realm,
         dataset: binding.dataset,
         source_selection:
           selection
           |> put_selected_binding(binding)
           |> put_selected_data_source(data_source)
           |> put_selection_strategy(:historical_binding)
       }}
    end
  end

  def resolve_segments(
        %PlannedSourceRequest{} = request,
        data_sources,
        intervals,
        opts
      ) do
    case source_binding_range(opts) do
      {%DateTime{} = from, %DateTime{} = to} ->
        with {:ok, segments} <- select_segments(request, intervals, from, to) do
          resolve_segment_bindings(request, data_sources, segments)
        end

      nil ->
        with {:ok, resolved_binding} <- resolve(request, data_sources, intervals, opts) do
          {:ok, [resolved_binding]}
        end
    end
  end

  defp select_interval(%PlannedSourceRequest{} = request, intervals, %DateTime{} = at) do
    selection = historical_source_selection(request, intervals, at)

    matching_intervals =
      intervals
      |> Enum.filter(&(interval_matches?(&1, request) and DataBindingInterval.contains?(&1, at)))
      |> Enum.sort_by(&interval_selection_sort_key/1)

    case matching_intervals do
      [interval | _rest] ->
        {:ok, interval, select_candidate(selection, interval.binding_id)}

      [] ->
        {:error,
         warning(
           request,
           :missing_source_binding,
           :error,
           "No source binding matches request",
           historical_missing_binding_details(request, selection, at)
         )}
    end
  end

  defp select_segments(
         %PlannedSourceRequest{} = request,
         intervals,
         %DateTime{} = from,
         %DateTime{} = to
       ) do
    matching_intervals =
      intervals
      |> Enum.filter(
        &(interval_matches?(&1, request) and DataBindingInterval.overlaps?(&1, from, to))
      )
      |> Enum.sort_by(&interval_selection_sort_key/1)

    if matching_intervals == [] do
      {:error,
       warning(request, :missing_source_binding, :error, "No source binding matches request", %{
         organization_id: request.organization_id,
         mission_id: request.mission_id,
         logical_source: request.logical_source,
         realm: requested_realm(request),
         from: from,
         to: to
       })}
    else
      build_selected_segments(request, matching_intervals, from, to)
    end
  end

  defp build_selected_segments(
         %PlannedSourceRequest{} = request,
         matching_intervals,
         %DateTime{} = from,
         %DateTime{} = to
       ) do
    boundaries =
      matching_intervals
      |> Enum.flat_map(&interval_boundaries(&1, from, to))
      |> Kernel.++([from, to])
      |> Enum.uniq_by(&DateTime.to_unix(&1, :microsecond))
      |> Enum.sort(DateTime)

    boundaries
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reject(fn [segment_from, segment_to] ->
      DateTime.compare(segment_from, segment_to) != :lt
    end)
    |> Enum.reduce_while({:ok, []}, fn [segment_from, segment_to], {:ok, segments} ->
      case select_segment_interval(matching_intervals, segment_from, segment_to) do
        {:ok, interval} ->
          selection =
            request
            |> historical_source_selection(matching_intervals, segment_from)
            |> select_candidate(interval.binding_id)
            |> put_selection_strategy(:historical_segment)
            |> Map.put(:segment_from, segment_from)
            |> Map.put(:segment_to, segment_to)

          {:cont,
           {:ok,
            segments ++
              [%{interval: interval, from: segment_from, to: segment_to, selection: selection}]}}

        :error ->
          {:halt,
           {:error,
            warning(
              request,
              :missing_source_binding,
              :error,
              "Source binding range contains an uncovered interval",
              %{
                organization_id: request.organization_id,
                mission_id: request.mission_id,
                logical_source: request.logical_source,
                realm: requested_realm(request),
                from: segment_from,
                to: segment_to,
                source_selection:
                  request
                  |> historical_source_selection(matching_intervals, segment_from)
                  |> put_selection_strategy(:historical_segment)
              }
            )}}
      end
    end)
    |> case do
      {:ok, segments} -> {:ok, merge_adjacent_segments(segments)}
      {:error, warning} -> {:error, warning}
    end
  end

  defp interval_boundaries(
         %DataBindingInterval{} = interval,
         %DateTime{} = from,
         %DateTime{} = to
       ) do
    [
      later_datetime(DataBindingInterval.effective_start(interval), from),
      earlier_datetime(DataBindingInterval.effective_end(interval) || to, to)
    ]
  end

  defp select_segment_interval(matching_intervals, %DateTime{} = from, %DateTime{} = to) do
    matching_intervals
    |> Enum.filter(
      &(DataBindingInterval.contains?(&1, from) and DataBindingInterval.overlaps?(&1, from, to))
    )
    |> Enum.sort_by(&interval_selection_sort_key/1)
    |> case do
      [interval | _rest] -> {:ok, interval}
      [] -> :error
    end
  end

  defp merge_adjacent_segments([]), do: []

  defp merge_adjacent_segments([segment | rest]) do
    Enum.reduce(rest, [segment], fn segment, [previous | acc] ->
      if same_segment_interval?(previous, segment) and
           DateTime.compare(previous.to, segment.from) == :eq do
        [%{previous | to: segment.to} | acc]
      else
        [segment, previous | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp same_segment_interval?(left, right) do
    interval_identity(left.interval) == interval_identity(right.interval)
  end

  defp resolve_segment_bindings(%PlannedSourceRequest{} = request, data_sources, segments) do
    segments
    |> Enum.reduce_while({:ok, []}, fn segment, {:ok, resolved_segments} ->
      binding = DataBindingInterval.to_binding(segment.interval)

      selection =
        segment
        |> Map.get(:selection, %{})
        |> put_selected_binding(binding)

      case fetch_data_source(binding, data_sources, request, selection) do
        {:ok, data_source} ->
          resolved_binding = %ResolvedSourceBinding{
            binding: binding,
            binding_interval: segment.interval,
            segment_from: segment.from,
            segment_to: segment.to,
            data_source: data_source,
            realm: binding.realm,
            dataset: binding.dataset,
            source_selection:
              selection
              |> put_selected_data_source(data_source)
              |> put_selection_strategy(:historical_segment)
          }

          {:cont, {:ok, resolved_segments ++ [resolved_binding]}}

        {:error, warning} ->
          {:halt, {:error, warning}}
      end
    end)
  end

  defp validate_source_binding_range(%PlannedSourceRequest{} = request, intervals, opts) do
    case source_binding_range(opts) do
      {%DateTime{} = from, %DateTime{} = to} ->
        matching_intervals =
          intervals
          |> Enum.filter(
            &(interval_matches?(&1, request) and DataBindingInterval.overlaps?(&1, from, to))
          )
          |> Enum.sort_by(&interval_selection_sort_key/1)

        interval_identities =
          matching_intervals
          |> Enum.map(&interval_identity/1)
          |> Enum.uniq()

        if length(interval_identities) > 1 do
          {:error,
           warning(
             request,
             :source_binding_interval_ambiguous,
             :error,
             "Source request spans multiple source binding intervals",
             %{
               organization_id: request.organization_id,
               mission_id: request.mission_id,
               logical_source: request.logical_source,
               realm: requested_realm(request),
               from: from,
               to: to,
               intervals:
                 matching_intervals
                 |> Enum.sort_by(&interval_chronological_sort_key/1)
                 |> Enum.map(&DataBindingInterval.metadata/1)
             }
           )}
        else
          :ok
        end

      nil ->
        :ok
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
      {:ok, AdapterRegistry.materialize(data_source, binding.logical_source)}
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

  defp historical_source_selection(%PlannedSourceRequest{} = request, intervals, %DateTime{} = at) do
    candidates = Enum.map(intervals, &interval_candidate(request, &1, at))

    %{
      strategy: :historical_binding,
      logical_source: request.logical_source,
      requested_realm: requested_realm(request),
      requested_time_mode: requested_time_mode(request),
      requested_time_axis: requested_time_axis(request),
      replay_run_id: requested_replay_run_id(request),
      requested_source_binding_id: source_context_value(request, :source_binding_id),
      requested_data_source_id: source_context_value(request, :data_source_id),
      requested_dataset: source_context_value(request, :dataset),
      source_binding_at: at,
      candidate_count: length(candidates),
      eligible_candidate_count: Enum.count(candidates, &(&1.reasons == [])),
      candidates: candidates
    }
    |> drop_nil_values()
  end

  defp interval_candidate(
         %PlannedSourceRequest{} = request,
         %DataBindingInterval{} = interval,
         at
       ) do
    reasons = interval_rejection_reasons(request, interval, at)

    %{
      binding_id: interval.binding_id,
      data_source_id: interval.data_source_id,
      logical_source: interval.logical_source,
      realm: interval.realm,
      dataset: interval.dataset,
      priority: interval.priority,
      status: interval.status,
      organization_id: interval.organization_id,
      mission_id: interval.mission_id,
      started_at: interval.started_at,
      ended_at: interval.ended_at,
      data_binding_event_id: interval.data_binding_event_id,
      binding_version: interval.binding_version,
      decision: if(reasons == [], do: :eligible, else: :rejected),
      reasons: reasons
    }
    |> drop_nil_values()
  end

  defp historical_missing_binding_details(
         %PlannedSourceRequest{} = request,
         selection,
         %DateTime{} = at
       ) do
    candidates = Map.get(selection, :candidates, [])

    effective_identity_candidates =
      Enum.filter(candidates, fn candidate ->
        candidate
        |> Map.get(:reasons, [])
        |> Enum.all?(&(&1 == :interval_not_effective))
      end)

    nearest_candidate =
      nearest_interval_candidate(effective_identity_candidates, at) ||
        nearest_interval_candidate(candidates, at)

    %{
      organization_id: request.organization_id,
      mission_id: request.mission_id,
      logical_source: request.logical_source,
      realm: requested_realm(request),
      source_binding_at: at,
      source_binding_miss_reason:
        source_binding_miss_reason(
          nearest_candidate,
          effective_identity_candidates,
          candidates,
          at
        ),
      source_selection: selection
    }
    |> maybe_put_nearest_interval(nearest_candidate)
  end

  defp nearest_interval_candidate([], _at), do: nil

  defp nearest_interval_candidate(candidates, %DateTime{} = at) when is_list(candidates) do
    candidates
    |> Enum.filter(&(datetime?(Map.get(&1, :started_at)) or datetime?(Map.get(&1, :ended_at))))
    |> Enum.min_by(&interval_distance(&1, at), fn -> nil end)
  end

  defp interval_distance(candidate, %DateTime{} = at) when is_map(candidate) do
    started_at = Map.get(candidate, :started_at)
    ended_at = Map.get(candidate, :ended_at)

    cond do
      datetime?(started_at) and DateTime.compare(at, started_at) == :lt ->
        abs(DateTime.diff(started_at, at, :microsecond))

      datetime?(ended_at) and DateTime.compare(at, ended_at) != :lt ->
        abs(DateTime.diff(at, ended_at, :microsecond))

      true ->
        0
    end
  end

  defp source_binding_miss_reason(nil, _effective_identity_candidates, [], _at),
    do: :no_source_binding_intervals

  defp source_binding_miss_reason(nil, _effective_identity_candidates, _candidates, _at),
    do: :no_matching_source_binding_interval

  defp source_binding_miss_reason(
         candidate,
         [_ | _],
         _candidates,
         %DateTime{} = at
       )
       when is_map(candidate) do
    started_at = Map.get(candidate, :started_at)
    ended_at = Map.get(candidate, :ended_at)

    cond do
      datetime?(started_at) and DateTime.compare(at, started_at) == :lt ->
        :source_binding_not_started_at_requested_time

      datetime?(ended_at) and DateTime.compare(at, ended_at) != :lt ->
        :source_binding_expired_at_requested_time

      true ->
        :source_binding_not_effective_at_requested_time
    end
  end

  defp source_binding_miss_reason(_candidate, _effective_identity_candidates, _candidates, _at),
    do: :no_matching_source_binding_interval

  defp maybe_put_nearest_interval(details, nil), do: details

  defp maybe_put_nearest_interval(details, candidate) when is_map(candidate) do
    details
    |> Map.put(:nearest_source_binding_id, Map.get(candidate, :binding_id))
    |> Map.put(:nearest_data_source_id, Map.get(candidate, :data_source_id))
    |> Map.put(:nearest_source_binding_started_at, Map.get(candidate, :started_at))
    |> Map.put(:nearest_source_binding_ended_at, Map.get(candidate, :ended_at))
    |> Map.put(:nearest_source_binding_status, Map.get(candidate, :status))
    |> drop_nil_values()
  end

  defp interval_rejection_reasons(
         %PlannedSourceRequest{} = request,
         %DataBindingInterval{} = interval,
         %DateTime{} = at
       ) do
    []
    |> maybe_add_reason(
      interval.logical_source != request.logical_source,
      :logical_source_mismatch
    )
    |> maybe_add_reason(
      not matches_scope?(interval.organization_id, request.organization_id),
      :organization_mismatch
    )
    |> maybe_add_reason(
      not matches_scope?(interval.mission_id, request.mission_id),
      :mission_mismatch
    )
    |> maybe_add_reason(
      normalize_realm(interval.realm) != normalize_realm(requested_realm(request)),
      :realm_mismatch
    )
    |> maybe_add_reason(
      not matches_context_value?(
        interval.binding_id,
        source_context_value(request, :source_binding_id)
      ),
      :source_binding_filter_mismatch
    )
    |> maybe_add_reason(
      not matches_context_value?(
        interval.data_source_id,
        source_context_value(request, :data_source_id)
      ),
      :data_source_filter_mismatch
    )
    |> maybe_add_reason(
      not matches_context_value?(interval.dataset, source_context_value(request, :dataset)),
      :dataset_filter_mismatch
    )
    |> maybe_add_reason(not DataBindingInterval.contains?(interval, at), :interval_not_effective)
    |> Enum.reverse()
  end

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

  defp datetime?(%DateTime{}), do: true
  defp datetime?(_value), do: false

  defp interval_matches?(%DataBindingInterval{} = interval, %PlannedSourceRequest{} = request) do
    interval.logical_source == request.logical_source and
      matches_scope?(interval.organization_id, request.organization_id) and
      matches_scope?(interval.mission_id, request.mission_id) and
      normalize_realm(interval.realm) == normalize_realm(requested_realm(request)) and
      matches_context_value?(
        interval.binding_id,
        source_context_value(request, :source_binding_id)
      ) and
      matches_context_value?(
        interval.data_source_id,
        source_context_value(request, :data_source_id)
      ) and
      matches_context_value?(interval.dataset, source_context_value(request, :dataset))
  end

  defp matches_scope?(nil, _requested), do: true
  defp matches_scope?(scope, requested), do: scope == requested

  defp matches_context_value?(_actual, nil), do: true
  defp matches_context_value?(_actual, ""), do: true
  defp matches_context_value?(actual, requested), do: actual == requested

  defp interval_selection_sort_key(%DataBindingInterval{} = interval) do
    {
      -scope_specificity(interval.organization_id),
      -scope_specificity(interval.mission_id),
      interval.priority,
      -DateTime.to_unix(interval.started_at, :microsecond),
      interval.binding_id
    }
  end

  defp interval_chronological_sort_key(%DataBindingInterval{} = interval) do
    {DateTime.to_unix(interval.started_at, :microsecond), interval.binding_id}
  end

  defp interval_identity(%DataBindingInterval{} = interval) do
    {
      interval.binding_id,
      interval.data_binding_event_id,
      interval.binding_version,
      interval.status,
      interval.data_source_id,
      interval.dataset,
      interval.started_at,
      interval.ended_at
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

  defp source_context_value(%PlannedSourceRequest{} = request, key) do
    DataContext.source_value(request.data_context, request.logical_source, key)
  end

  defp source_binding_at(opts) do
    case Keyword.get(opts, :source_binding_at) do
      %DateTime{} = at -> at
      _other -> nil
    end
  end

  defp source_binding_range(opts) do
    opts
    |> Keyword.get(:source_binding_range)
    |> normalize_source_binding_range()
  end

  defp normalize_source_binding_range(%{from: %DateTime{} = from, to: %DateTime{} = to}) do
    ordered_range(from, to)
  end

  defp normalize_source_binding_range(%{"from" => %DateTime{} = from, "to" => %DateTime{} = to}) do
    ordered_range(from, to)
  end

  defp normalize_source_binding_range(range) when is_list(range) do
    from = Keyword.get(range, :from)
    to = Keyword.get(range, :to)

    case {from, to} do
      {%DateTime{} = from, %DateTime{} = to} -> ordered_range(from, to)
      _other -> nil
    end
  end

  defp normalize_source_binding_range(_range), do: nil

  defp ordered_range(%DateTime{} = from, %DateTime{} = to) do
    if DateTime.compare(from, to) == :lt do
      {from, to}
    else
      nil
    end
  end

  defp later_datetime(%DateTime{} = left, %DateTime{} = right) do
    if DateTime.compare(left, right) == :lt, do: right, else: left
  end

  defp earlier_datetime(%DateTime{} = left, %DateTime{} = right) do
    if DateTime.compare(left, right) == :gt, do: right, else: left
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
