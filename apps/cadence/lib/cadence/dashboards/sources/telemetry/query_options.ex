defmodule Cadence.Dashboards.Sources.Telemetry.QueryOptions do
  @moduledoc false

  alias Cadence.Dashboards.{
    DataContext,
    DataLinks,
    PlannedSourceRequest,
    ResolveWarning,
    ScopeContext,
    TelemetryActions
  }

  alias Cadence.Dashboards.Sources.Telemetry.FrameContext
  alias Cadence.Reads.OperationalState
  alias Cadence.Telemetry.SelectionPolicy

  @default_limit 10_000

  @spec history(PlannedSourceRequest.t(), map() | nil, keyword()) ::
          {keyword(), [ResolveWarning.t()]}
  def history(%PlannedSourceRequest{} = request, source_binding, source_opts) do
    {time_opts, time_warnings} = bounded_history_time_opts(request, source_opts)

    opts =
      [
        realm: FrameContext.realm(request, source_binding),
        replay_run_id: FrameContext.replay_run_id(request),
        data_source_id: FrameContext.data_source_id(request, source_binding),
        source_binding_id: FrameContext.source_binding_id(source_binding),
        dataset: FrameContext.dataset(source_binding),
        spacecraft_id: spacecraft_id(request.scope_context),
        source_endpoint_ids: source_endpoint_ids(request, source_opts),
        limit: raw_point_limit(request),
        order: :asc
      ]
      |> Kernel.++(time_opts)
      |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)

    {opts ++ selection_policy_opts(request) ++ connection_opts(source_opts), time_warnings}
  end

  @spec decimated(PlannedSourceRequest.t(), map() | nil, keyword()) ::
          {keyword(), [ResolveWarning.t()]}
  def decimated(%PlannedSourceRequest{} = request, source_binding, source_opts) do
    {opts, time_warnings} = history(request, source_binding, source_opts)

    decimation_opts =
      [
        target_points: target_points(request),
        bucket_width_ms: bucket_width_ms(request),
        decimation: :native_min_max_envelope
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    {opts ++ decimation_opts, time_warnings}
  end

  @spec latest(PlannedSourceRequest.t(), map() | nil, keyword()) :: keyword()
  def latest(%PlannedSourceRequest{} = request, source_binding, opts) do
    [
      realm: FrameContext.realm(request, source_binding),
      replay_run_id: FrameContext.replay_run_id(request),
      data_source_id: FrameContext.data_source_id(request, source_binding),
      source_binding_id: FrameContext.source_binding_id(source_binding),
      dataset: FrameContext.dataset(source_binding),
      spacecraft_id: spacecraft_id(request.scope_context),
      source_endpoint_ids: source_endpoint_ids(request, opts),
      to_receipt_time: latest_as_of_receipt_time(request)
    ]
    |> Kernel.++(selection_policy_opts(request))
    |> Kernel.++(connection_opts(opts))
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
  end

  @spec watermark(PlannedSourceRequest.t(), map() | nil, keyword()) :: keyword()
  def watermark(%PlannedSourceRequest{} = request, source_binding, opts) do
    {from_receipt_time, to_receipt_time, _warnings} = receipt_time_bounds(request)

    [
      realm: FrameContext.realm(request, source_binding),
      data_source_id: FrameContext.data_source_id(request, source_binding),
      source_binding_id: FrameContext.source_binding_id(source_binding),
      dataset: FrameContext.dataset(source_binding),
      replay_run_id: FrameContext.replay_run_id(request),
      spacecraft_id: spacecraft_id(request.scope_context),
      source_endpoint_ids: source_endpoint_ids(request, opts),
      from_receipt_time: from_receipt_time,
      to_receipt_time: to_receipt_time
    ]
    |> Kernel.++(selection_policy_opts(request))
    |> Kernel.++(connection_opts(opts))
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
  end

  @spec receipt_time_bounds(PlannedSourceRequest.t()) ::
          {DateTime.t() | nil, DateTime.t() | nil, [ResolveWarning.t()]}
  def receipt_time_bounds(%PlannedSourceRequest{} = request) do
    {time_bounds, warnings} = bounded_history_time_opts(request, [])

    {
      Keyword.get(time_bounds, :from_receipt_time),
      Keyword.get(time_bounds, :to_receipt_time),
      warnings
    }
  end

  @spec latest_warnings(PlannedSourceRequest.t()) :: [ResolveWarning.t()]
  def latest_warnings(%PlannedSourceRequest{} = request) do
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
              requested_axis: FrameContext.time_axis(request),
              fallback: :latest_projection
            }
          )
        ]
    end
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

  defp bounded_history_time_opts(%PlannedSourceRequest{} = request, source_opts) do
    requested_axis = FrameContext.time_axis(request)
    effective_axis = effective_bounded_history_time_axis(request, source_opts)
    {from_time, to_time} = bounded_history_time_range(request, source_opts)

    bounded_history_time_opts_for_axis(
      request,
      requested_axis,
      effective_axis,
      from_time,
      to_time,
      source_opts
    )
  end

  defp bounded_history_time_range(%PlannedSourceRequest{} = request, source_opts) do
    from_time = first_context_value(request.time_context, [:from, :start, :start_time])
    to_time = first_context_value(request.time_context, [:to, :end, :end_time])

    case {from_time, to_time, live_time_context?(request.time_context),
          live_window_seconds(request.time_context)} do
      {nil, nil, true, window_seconds} when is_integer(window_seconds) ->
        to_time = live_window_now(source_opts)
        {DateTime.add(to_time, -window_seconds, :second), to_time}

      _explicit_or_unbounded ->
        {from_time, to_time}
    end
  end

  defp live_time_context?(time_context) do
    first_context_value(time_context, [:mode]) in [:live, "live"]
  end

  defp live_window_seconds(time_context) do
    case first_context_value(time_context, [:window_seconds]) do
      window_seconds when is_integer(window_seconds) and window_seconds > 0 -> window_seconds
      _invalid_or_missing -> nil
    end
  end

  defp live_window_now(source_opts) do
    case Keyword.get(source_opts, :now) do
      %DateTime{} = now -> DateTime.truncate(now, :microsecond)
      _missing -> DateTime.utc_now()
    end
  end

  defp effective_bounded_history_time_axis(%PlannedSourceRequest{} = request, source_opts) do
    requested_axis = FrameContext.time_axis(request)
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

  defp latest_as_of_receipt_time(%PlannedSourceRequest{} = request) do
    if latest_as_of_supported?(request) do
      first_context_value(request.time_context, [:to, :end, :end_time])
    end
  end

  defp latest_as_of_supported?(%PlannedSourceRequest{} = request) do
    requested_axis = FrameContext.time_axis(request)
    to_time = first_context_value(request.time_context, [:to, :end, :end_time])

    not is_nil(to_time) and requested_axis in [nil, :receipt_time]
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
      fetch_contact_source_endpoint_ids(
        request.organization_id,
        request.mission_id,
        contact_id,
        opts
      )
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
      Keyword.get(opts, :fetch_scheduled_contact, &OperationalState.fetch_scheduled_contact/3)

    fetch_scheduled_contact.(organization_id, mission_id, contact_id)
  end

  defp fetch_realized_contact(organization_id, mission_id, contact_id, opts) do
    fetch_realized_contact =
      Keyword.get(opts, :fetch_realized_contact, &OperationalState.fetch_realized_contact/3)

    fetch_realized_contact.(organization_id, mission_id, contact_id)
  end

  defp contact_source_endpoint_refs(contact) when is_map(contact) do
    contact
    |> context_value(:source_endpoint_refs)
    |> normalize_source_endpoint_ids()
  end

  defp contact_source_endpoint_refs(_contact), do: []

  defp raw_point_limit(%PlannedSourceRequest{sampling: sampling}) do
    case context_value(sampling, :max_raw_points) || context_value(sampling, :limit) do
      limit when is_integer(limit) and limit > 0 -> min(limit, @default_limit)
      _invalid -> @default_limit
    end
  end

  defp target_points(%PlannedSourceRequest{sampling: sampling}) do
    case context_value(sampling, :target_points) do
      value when is_integer(value) and value > 0 -> value
      _invalid -> nil
    end
  end

  defp bucket_width_ms(%PlannedSourceRequest{sampling: sampling}) do
    case context_value(sampling, :bucket_width_ms) do
      value when is_integer(value) and value > 0 -> value
      _invalid -> nil
    end
  end

  defp spacecraft_id(scope_context), do: ScopeContext.scope_id(scope_context, :spacecraft)

  defp time_range_requested?(time_context) do
    mode = time_context |> context_value(:mode) |> normalize_atom()

    mode in [:archive, :range] or
      not is_nil(first_context_value(time_context, [:from, :start, :start_time])) or
      not is_nil(first_context_value(time_context, [:to, :end, :end_time]))
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
        |> put_warning_actions(request, warning_observable_id(request, details)),
      links: DataLinks.request_observable_links(request, source: :warning)
    }
  end

  defp put_warning_actions(details, %PlannedSourceRequest{} = request, observable_id) do
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

  defp normalize_source_endpoint_ids(ids) when is_list(ids) do
    ids
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.uniq()
  end

  defp normalize_source_endpoint_ids(id) when is_binary(id) and id != "", do: [id]
  defp normalize_source_endpoint_ids(_ids), do: []

  defp first_context_value(context, keys) do
    Enum.find_value(keys, &context_value(context, &1))
  end

  defp context_value(context, key) when is_map(context) and is_atom(key) do
    Map.get(context, key, Map.get(context, Atom.to_string(key)))
  end

  defp context_value(_context, _key), do: nil

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
