defmodule Cadence.Dashboards.SourceRequestPlanning do
  @moduledoc """
  Derives runtime contexts and sampling policy for dashboard source requests.

  This module owns the time-, data-, scope-, and placement-sensitive planning
  needed before the dashboard engine validates or executes a request.
  """

  alias Cadence.Dashboards.{
    DashboardResolveRequest,
    DataContext,
    LimitContext,
    Placement,
    PlacementExpansion,
    PlannedSourceRequest,
    ResolveWarning,
    ScopeContext,
    TimeContext
  }

  @spec runtime_contexts(DashboardResolveRequest.t(), Placement.t()) ::
          {map(), [ResolveWarning.t()]}
  def runtime_contexts(%DashboardResolveRequest{} = request, %Placement{} = placement) do
    defaults = request.document.defaults || %{}

    time_context =
      TimeContext.resolve(request.time_context, Map.get(defaults, "time") || %{}, nil)

    data_context =
      request.data_context
      |> DataContext.resolve(Map.get(defaults, "data") || %{}, placement.data_override)
      |> default_replay_realm_if_implicit(
        time_context,
        request.data_context,
        placement.data_override
      )

    contexts = %{
      time: time_context,
      scope:
        ScopeContext.resolve(
          request.scope_context,
          Map.get(defaults, "scope") || %{},
          placement.scope_override
        ),
      data: data_context,
      limit:
        LimitContext.resolve(
          request.limit_context,
          Map.get(defaults, "limits") || %{},
          placement.limit_override
        )
    }

    {contexts, context_warnings(contexts, placement)}
  end

  @spec source_time_context(term(), atom(), map()) :: term()
  def source_time_context(time_context, :events, _sampling) do
    put_time_axis(time_context, :occurred_at)
  end

  def source_time_context(time_context, :limits, sampling) do
    if Map.get(sampling, :temporal?, false) do
      put_time_axis(time_context, :receipt_time)
    else
      time_context
    end
  end

  def source_time_context(time_context, :telemetry, _sampling), do: time_context
  def source_time_context(time_context, _source, _sampling), do: time_context

  @spec source_backed_overlay_specs(map(), Placement.t()) :: [map()]
  def source_backed_overlay_specs(widget_type, %Placement{} = placement) do
    requested_overlays = Map.get(placement.widget_def.binding, :overlays, [])

    widget_type.data_contract
    |> Map.get(:overlays, [])
    |> Enum.filter(fn overlay_spec ->
      source_backed_overlay?(overlay_spec) and
        (Map.get(overlay_spec, :required?, false) or
           Map.get(overlay_spec, :role) in requested_overlays)
    end)
  end

  @spec unresolved_overlays(map(), map()) :: [term()]
  def unresolved_overlays(binding, widget_type) do
    source_backed_roles =
      widget_type
      |> Map.get(:data_contract, %{})
      |> Map.get(:overlays, [])
      |> Enum.filter(&source_backed_overlay?/1)
      |> Enum.map(&Map.get(&1, :role))

    binding
    |> Map.get(:overlays, [])
    |> Enum.reject(&(&1 in source_backed_roles))
  end

  @spec sampling(map(), map(), DashboardResolveRequest.t(), Placement.t(), map()) :: map()
  def sampling(binding, frame_spec, request, placement, widget_type) do
    poll_latest? = poll_latest_live_request?(request, widget_type, frame_spec)

    mode =
      if poll_latest? do
        :latest
      else
        Map.get(binding, :sampling) || Map.get(frame_spec, :sampling)
      end

    %{
      mode: mode,
      target_points: target_points(placement_size(request, placement.placement_id)),
      max_raw_points: 10_000,
      temporal?: if(poll_latest?, do: false, else: Map.get(frame_spec, :temporal?, false))
    }
    |> maybe_put_sampling_products(frame_spec)
    |> maybe_put_sampling_families(frame_spec)
  end

  @spec overlay_samplings(
          map(),
          [map()],
          DashboardResolveRequest.t(),
          Placement.t(),
          map()
        ) :: [map()]
  def overlay_samplings(
        %{source: :limits},
        primary_frame_specs,
        request,
        _placement,
        widget_type
      ) do
    if poll_latest_live_request?(request, widget_type) do
      [latest_limit_overlay_sampling()]
    else
      temporal? = Enum.any?(primary_frame_specs, &Map.get(&1, :temporal?, false))

      decimated? =
        Enum.any?(primary_frame_specs, &(Map.get(&1, :sampling) == :decimated_envelope))

      cond do
        temporal? and decimated? ->
          [
            limit_analysis_buckets_overlay_sampling(),
            limit_definition_intervals_overlay_sampling()
          ]

        temporal? ->
          [limit_event_history_overlay_sampling(), limit_definition_intervals_overlay_sampling()]

        true ->
          [latest_limit_overlay_sampling()]
      end
    end
  end

  def overlay_samplings(
        %{source: :events},
        primary_frame_specs,
        request,
        placement,
        _widget_type
      ) do
    temporal? = Enum.any?(primary_frame_specs, &Map.get(&1, :temporal?, false))

    source_watermark_context =
      source_watermark_overlay_context(primary_frame_specs, request, placement)

    [
      %{
        mode: :event_history,
        products: [
          :contact_intervals,
          :mission_timeline,
          :source_health_transitions,
          :source_watermark_events,
          :source_capability_postures,
          :telemetry_backfill_lifecycle,
          :telemetry_revision_decisions
        ],
        families: [
          :contacts,
          :mission_timeline,
          :source_health,
          :source_watermarks,
          :source_capabilities,
          :telemetry_backfills,
          :telemetry_revisions
        ],
        temporal?: temporal?,
        source_watermark: source_watermark_context,
        limit: 500
      }
      |> drop_empty_map_value(:source_watermark)
    ]
  end

  @spec overlay_data_context(term(), atom()) :: term()
  def overlay_data_context(%DataContext{} = data_context, _source) do
    %DataContext{data_context | data_source_id: nil, source_binding_id: nil, dataset: nil}
  end

  def overlay_data_context(data_context, _source), do: data_context

  @spec live_append_eligible?(DashboardResolveRequest.t()) :: boolean()
  def live_append_eligible?(%DashboardResolveRequest{} = request) do
    not snapshot_time_context?(request)
  end

  @spec snapshot_time_context?(DashboardResolveRequest.t()) :: boolean()
  def snapshot_time_context?(%DashboardResolveRequest{} = request) do
    time_context_mode(request) in [:archive, :range, :replay_run]
  end

  @spec time_context_metadata(DashboardResolveRequest.t()) :: map()
  def time_context_metadata(%DashboardResolveRequest{} = request) do
    time_context =
      TimeContext.resolve(request.time_context, request_document_time_defaults(request), nil)

    %{
      mode: normalized_time_mode(time_context.mode),
      axis: normalized_time_axis(time_context.axis),
      from: time_context.from || time_context.start || time_context.start_time,
      to: time_context.to || time_context.end || time_context.end_time,
      replay_run_id: time_context.replay_run_id
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  @spec source_request_snapshot?(PlannedSourceRequest.t()) :: boolean()
  def source_request_snapshot?(%PlannedSourceRequest{} = source_request) do
    source_request
    |> source_request_time_mode()
    |> Kernel.in([:archive, :range, :replay_run])
  end

  @spec source_registry_opts(PlannedSourceRequest.t(), keyword()) :: keyword()
  def source_registry_opts(%PlannedSourceRequest{} = source_request, opts) when is_list(opts) do
    opts = maybe_put_replay_operational_interval_at(opts, source_request)

    case source_binding_time_window(source_request) do
      %{at: %DateTime{} = at} = window ->
        opts
        |> Keyword.put_new(:source_binding_at, at)
        |> maybe_put_source_binding_range(Map.get(window, :range))

      nil ->
        opts
    end
  end

  @spec placement_size(DashboardResolveRequest.t(), term()) :: map()
  def placement_size(
        %DashboardResolveRequest{interaction_context: interaction_context},
        placement_id
      ) do
    placement_sizes =
      Map.get(
        interaction_context,
        :placement_sizes,
        Map.get(interaction_context, "placement_sizes", %{})
      )

    Map.get(placement_sizes, placement_id) ||
      Map.get(placement_sizes, PlacementExpansion.authored_placement_id(placement_id), %{})
  end

  @spec live_tick_refreshable?(PlannedSourceRequest.t()) :: boolean()
  def live_tick_refreshable?(%PlannedSourceRequest{
        logical_source: :telemetry,
        sampling: %{mode: :latest}
      }),
      do: true

  def live_tick_refreshable?(%PlannedSourceRequest{
        logical_source: :limits,
        sampling: %{mode: mode}
      })
      when mode in [:latest, :latest_state],
      do: true

  def live_tick_refreshable?(%PlannedSourceRequest{
        logical_source: :operational_observables,
        sampling: %{mode: :latest}
      }),
      do: true

  def live_tick_refreshable?(%PlannedSourceRequest{}), do: false

  defp put_time_axis(%TimeContext{} = time_context, axis),
    do: %TimeContext{time_context | axis: axis}

  defp put_time_axis(time_context, axis) when is_map(time_context),
    do: Map.put(time_context, :axis, axis)

  defp put_time_axis(time_context, _axis), do: time_context

  defp source_backed_overlay?(%{source: :limits}), do: true
  defp source_backed_overlay?(%{source: :events}), do: true
  defp source_backed_overlay?(_overlay_spec), do: false

  defp maybe_put_sampling_products(sampling, %{products: products})
       when is_list(products) and products != [] do
    Map.put(sampling, :products, products)
  end

  defp maybe_put_sampling_products(sampling, _frame_spec), do: sampling

  defp maybe_put_sampling_families(sampling, %{families: families})
       when is_list(families) and families != [] do
    Map.put(sampling, :families, families)
  end

  defp maybe_put_sampling_families(sampling, _frame_spec), do: sampling

  defp source_watermark_overlay_context(primary_frame_specs, request, placement) do
    logical_source = primary_logical_source(primary_frame_specs, placement)
    data_context = placement_data_context(request, placement)

    %{
      logical_source: logical_source,
      data_source_id: data_context_value(data_context, logical_source, :data_source_id),
      source_binding_id: data_context_value(data_context, logical_source, :source_binding_id),
      dataset: data_context_value(data_context, logical_source, :dataset)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
    |> Map.new()
    |> non_empty_map()
  end

  defp primary_logical_source(primary_frame_specs, placement) do
    binding = placement.widget_def.binding || %{}

    Map.get(binding, :source) ||
      primary_frame_specs
      |> List.wrap()
      |> Enum.find_value(&Map.get(&1, :source))
  end

  defp placement_data_context(%DashboardResolveRequest{} = request, %Placement{} = placement) do
    defaults = request.document.defaults || %{}

    time_context =
      TimeContext.resolve(request.time_context, Map.get(defaults, "time") || %{}, nil)

    request.data_context
    |> DataContext.resolve(Map.get(defaults, "data") || %{}, placement.data_override)
    |> default_replay_realm_if_implicit(
      time_context,
      request.data_context,
      placement.data_override
    )
  end

  defp data_context_value(%DataContext{} = data_context, nil, key),
    do: Map.get(data_context, key)

  defp data_context_value(%DataContext{} = data_context, logical_source, key),
    do: DataContext.source_value(data_context, logical_source, key)

  defp non_empty_map(map) when map == %{}, do: nil
  defp non_empty_map(map), do: map

  defp drop_empty_map_value(map, key) do
    case Map.get(map, key) do
      nil -> Map.delete(map, key)
      %{} = value when map_size(value) == 0 -> Map.delete(map, key)
      _value -> map
    end
  end

  defp latest_limit_overlay_sampling do
    %{
      mode: :latest_state,
      products: [:latest_state],
      semantics_mode: :observed,
      temporal?: false
    }
  end

  defp limit_event_history_overlay_sampling do
    %{
      mode: :event_history,
      products: [:event_history],
      semantics_mode: :observed,
      temporal?: true,
      limit: 1_000
    }
  end

  defp limit_analysis_buckets_overlay_sampling do
    %{
      mode: :analysis_buckets,
      products: [:analysis_buckets],
      semantics_mode: :observed,
      temporal?: true,
      limit: 1_000
    }
  end

  defp limit_definition_intervals_overlay_sampling do
    %{
      mode: :definition_intervals,
      products: [:definition_intervals],
      semantics_mode: :observed,
      temporal?: true
    }
  end

  defp poll_latest_live_request?(request, widget_type, frame_spec) do
    poll_latest_live_request?(request, widget_type) and Map.get(frame_spec, :temporal?, false)
  end

  defp poll_latest_live_request?(%DashboardResolveRequest{} = request, widget_type) do
    request.resolve_mode in [:live_tick, :stream_append] and
      live_append_eligible?(request) and
      get_in(widget_type.data_contract, [:live_mode]) == :poll_latest
  end

  defp time_context_mode(%DashboardResolveRequest{} = request) do
    request
    |> time_context_metadata()
    |> Map.get(:mode)
  end

  defp request_document_time_defaults(%DashboardResolveRequest{document: %{defaults: defaults}})
       when is_map(defaults) do
    Map.get(defaults, "time") || Map.get(defaults, :time) || %{}
  end

  defp request_document_time_defaults(%DashboardResolveRequest{}), do: %{}

  defp normalized_time_mode(value),
    do: normalize_known_atom(value, [:live, :archive, :range, :replay_run])

  defp normalized_time_axis(value),
    do: normalize_known_atom(value, [:generation_time, :receipt_time])

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

  defp target_points(%{width_px: width}) when is_integer(width) and width > 0, do: width
  defp target_points(%{"width_px" => width}) when is_integer(width) and width > 0, do: width
  defp target_points(_placement_size), do: 1200

  defp default_replay_realm_if_implicit(
         %DataContext{} = data_context,
         %TimeContext{} = time_context,
         runtime_data_context,
         placement_data_override
       ) do
    cond do
      normalized_time_mode(time_context.mode) != :replay_run ->
        data_context

      explicit_data_realm?(runtime_data_context) or explicit_data_realm?(placement_data_override) ->
        data_context

      data_context.realm in [nil, :flight, "flight"] ->
        %DataContext{data_context | realm: :replay}

      true ->
        data_context
    end
  end

  defp explicit_data_realm?(%DataContext{realm: realm}), do: present_context_value?(realm)

  defp explicit_data_realm?(attrs) when is_map(attrs),
    do: present_context_value?(get_attr(attrs, :realm))

  defp explicit_data_realm?(_attrs), do: false

  defp present_context_value?(nil), do: false
  defp present_context_value?(""), do: false
  defp present_context_value?(_value), do: true

  defp context_warnings(contexts, %Placement{} = placement) do
    [
      {:time, TimeContext.validate(contexts.time)},
      {:scope, ScopeContext.validate(contexts.scope)},
      {:data, DataContext.validate(contexts.data)},
      {:limit, LimitContext.validate(contexts.limit)}
    ]
    |> Enum.reject(fn {_context, errors} -> errors == [] end)
    |> Enum.map(fn {context, errors} ->
      %ResolveWarning{
        code: :invalid_runtime_context,
        severity: :warning,
        scope: :placement,
        placement_id: placement.placement_id,
        message: "Dashboard runtime context contains unsupported values",
        details: %{context: context, errors: errors}
      }
    end)
  end

  defp maybe_put_replay_operational_interval_at(opts, %PlannedSourceRequest{} = source_request) do
    if source_request_time_mode(source_request) == :replay_run do
      case source_binding_range_window(source_request) do
        %{at: %DateTime{} = at} -> Keyword.put_new(opts, :operational_interval_at, at)
        _missing -> opts
      end
    else
      opts
    end
  end

  defp source_binding_time_window(%PlannedSourceRequest{} = source_request) do
    case source_request_time_mode(source_request) do
      :range -> source_binding_range_window(source_request)
      :archive -> source_binding_archive_window(source_request)
      _other -> nil
    end
  end

  defp source_binding_archive_window(%PlannedSourceRequest{} = source_request) do
    if source_request.logical_source == :telemetry and
         source_request_sampling_mode(source_request) in [
           :raw_series,
           :bounded_history,
           :bounded_raw_series
         ] do
      source_binding_range_window(source_request)
    else
      source_binding_point_window(source_request)
    end
  end

  defp source_binding_range_window(%PlannedSourceRequest{} = source_request) do
    {from, to} = source_request_time_bounds(source_request)

    cond do
      datetime?(from) and datetime?(to) and DateTime.compare(from, to) == :lt ->
        %{at: from, range: %{from: from, to: to}}

      datetime?(from) ->
        %{at: from}

      datetime?(to) ->
        %{at: to}

      true ->
        nil
    end
  end

  defp source_binding_point_window(%PlannedSourceRequest{} = source_request) do
    {from, to} = source_request_time_bounds(source_request)

    cond do
      datetime?(to) -> %{at: to}
      datetime?(from) -> %{at: from}
      true -> nil
    end
  end

  defp source_request_time_bounds(%PlannedSourceRequest{time_context: time_context}) do
    {
      get_attr(time_context, :from) || get_attr(time_context, :start) ||
        get_attr(time_context, :start_time),
      get_attr(time_context, :to) || get_attr(time_context, :end) ||
        get_attr(time_context, :end_time)
    }
  end

  defp maybe_put_source_binding_range(opts, nil), do: opts

  defp maybe_put_source_binding_range(opts, range) when is_map(range) do
    Keyword.put_new(opts, :source_binding_range, range)
  end

  defp datetime?(%DateTime{}), do: true
  defp datetime?(_value), do: false

  defp source_request_time_mode(%PlannedSourceRequest{time_context: time_context}) do
    time_context
    |> get_attr(:mode)
    |> normalized_time_mode()
  end

  defp source_request_sampling_mode(%PlannedSourceRequest{sampling: sampling}) do
    sampling
    |> get_attr(:mode)
    |> normalize_known_atom([:latest, :raw_series, :bounded_history, :bounded_raw_series])
  end

  defp get_attr(%_{} = attrs, key) when is_atom(key) do
    Map.get(attrs, key)
  end

  defp get_attr(attrs, key) when is_map(attrs) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  end

  defp get_attr(_attrs, _key), do: nil
end
