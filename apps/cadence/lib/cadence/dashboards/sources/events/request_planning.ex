defmodule Cadence.Dashboards.Sources.Events.RequestPlanning do
  @moduledoc false

  alias Cadence.Dashboards.{
    DataContext,
    DataLinks,
    PlannedSourceRequest,
    ResolveWarning,
    ScopeContext
  }

  alias Cadence.DataSources.SourceCapabilities

  @supported_products [
    :contact_intervals,
    :mission_timeline,
    :source_health_transitions,
    :source_watermark_events,
    :source_capability_postures,
    :telemetry_backfill_lifecycle,
    :telemetry_revision_decisions
  ]
  @supported_sampling [:event_history]
  @default_limit 500

  @spec capabilities() :: SourceCapabilities.t()
  def capabilities do
    SourceCapabilities.new(%{
      logical_source: :events,
      supported_sampling: @supported_sampling,
      supported_products: @supported_products,
      supported_time_axes: [:occurred_at],
      supported_value_types: [],
      supported_shapes: [:intervals, :events],
      supports_watermarks?: false,
      completeness: :partial,
      metadata: %{
        supported_families: [
          :contacts,
          :mission_timeline,
          :source_health,
          :source_watermarks,
          :source_capabilities,
          :telemetry_backfills,
          :telemetry_revisions
        ],
        unsupported_families: [
          :commands,
          :catalog_runtime,
          :replay,
          :eclipse,
          :flight_dynamics
        ]
      }
    })
  end

  def ensure_events_source(%PlannedSourceRequest{logical_source: :events}), do: :ok

  def ensure_events_source(%PlannedSourceRequest{} = request) do
    {:warning,
     warning(
       request,
       :unsupported_logical_source,
       :error,
       "Events adapter cannot resolve source",
       %{
         logical_source: request.logical_source
       }
     )}
  end

  def ensure_supported_sampling(%PlannedSourceRequest{} = request) do
    mode = sampling_mode(request)

    if mode in @supported_sampling do
      :ok
    else
      {:warning,
       warning(
         request,
         :unsupported_sampling,
         :warning,
         "Events source cannot resolve requested sampling mode",
         %{requested_mode: mode, supported_modes: @supported_sampling}
       )}
    end
  end

  def requested_products(%PlannedSourceRequest{} = request) do
    requested =
      request.sampling
      |> get_attr(:products)
      |> case do
        nil -> get_attr(request.sampling, :families)
        products -> products
      end
      |> List.wrap()

    requested = if requested == [], do: @supported_products, else: requested

    normalized =
      requested
      |> Enum.map(&normalize_product/1)
      |> Enum.reject(&is_nil/1)

    unsupported =
      requested
      |> Enum.reject(&(normalize_product(&1) in @supported_products))
      |> Enum.map(&stringify/1)

    products = Enum.filter(normalized, &(&1 in @supported_products)) |> Enum.uniq()

    warnings =
      case unsupported do
        [] ->
          []

        unsupported ->
          [
            warning(
              request,
              :unsupported_event_family,
              :warning,
              "Events source cannot resolve one or more requested event families",
              %{unsupported_families: unsupported, supported_products: @supported_products}
            )
          ]
      end

    case products do
      [] -> {@supported_products, warnings}
      products -> {products, warnings}
    end
  end

  def time_axis_warnings(%PlannedSourceRequest{} = request) do
    case time_axis(request) do
      axis when axis in [:occurred_at, nil] ->
        []

      axis ->
        [
          warning(
            request,
            :event_time_axis_mismatch,
            :info,
            "Events source uses operational occurrence time",
            %{requested_axis: axis, returned_axis: :occurred_at}
          )
        ]
    end
  end

  def common_meta(%PlannedSourceRequest{} = request, source_binding) do
    %{
      source_request_id: request.request_id,
      logical_source: :events,
      source_binding_id: source_binding_id(source_binding),
      dataset: dataset(source_binding),
      sampling: sampling_mode(request),
      realm: realm(request, source_binding),
      data_source_id: data_source_id(request, source_binding),
      replay_run_id: replay_run_id(request)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  def mission_timeline_projection(%PlannedSourceRequest{} = request) do
    if replay_run_id(request), do: :operational_events, else: :mission_events
  end

  def contact_interval_projection(%PlannedSourceRequest{} = request) do
    if replay_run_id(request), do: :operational_events, else: :contacts
  end

  def time_window(%PlannedSourceRequest{time_context: time_context}) do
    from =
      get_attr(time_context, :from) || get_attr(time_context, :start) ||
        get_attr(time_context, :start_time)

    to =
      get_attr(time_context, :to) || get_attr(time_context, :end) ||
        get_attr(time_context, :end_time)

    case {from, to} do
      {%DateTime{} = from, %DateTime{} = to} ->
        if DateTime.compare(from, to) == :lt, do: {from, to}, else: nil

      _other ->
        nil
    end
  end

  def request_limit(%PlannedSourceRequest{sampling: sampling}) do
    case get_attr(sampling, :limit) do
      limit when is_integer(limit) and limit > 0 -> min(limit, @default_limit)
      _other -> @default_limit
    end
  end

  def required_request_context(%PlannedSourceRequest{} = request, key) do
    case request_context_value(request, key) do
      value when is_binary(value) and value != "" ->
        {:ok, value}

      _other ->
        {:warning,
         warning(
           request,
           missing_context_code(key),
           :error,
           "Events source request is missing required context",
           %{
             required_context: key
           }
         )}
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
    get_attr(request.scope_context, key)
  end

  def sampling_mode(%PlannedSourceRequest{sampling: sampling}) do
    sampling
    |> get_attr(:mode)
    |> normalize_sampling_mode()
  end

  defp normalize_sampling_mode(:event_history), do: :event_history
  defp normalize_sampling_mode("event_history"), do: :event_history
  defp normalize_sampling_mode("event-history"), do: :event_history
  defp normalize_sampling_mode(:events), do: :event_history
  defp normalize_sampling_mode("events"), do: :event_history
  defp normalize_sampling_mode(:intervals), do: :event_history
  defp normalize_sampling_mode("intervals"), do: :event_history
  defp normalize_sampling_mode(value), do: value

  defp normalize_product(:contact_intervals), do: :contact_intervals
  defp normalize_product("contact_intervals"), do: :contact_intervals
  defp normalize_product("contact-intervals"), do: :contact_intervals
  defp normalize_product(:contacts), do: :contact_intervals
  defp normalize_product("contacts"), do: :contact_intervals
  defp normalize_product(:mission_timeline), do: :mission_timeline
  defp normalize_product("mission_timeline"), do: :mission_timeline
  defp normalize_product("mission-timeline"), do: :mission_timeline
  defp normalize_product(:mission_events), do: :mission_timeline
  defp normalize_product("mission_events"), do: :mission_timeline
  defp normalize_product("mission-events"), do: :mission_timeline
  defp normalize_product(:source_health), do: :source_health_transitions
  defp normalize_product("source_health"), do: :source_health_transitions
  defp normalize_product("source-health"), do: :source_health_transitions
  defp normalize_product(:source_health_transitions), do: :source_health_transitions
  defp normalize_product("source_health_transitions"), do: :source_health_transitions
  defp normalize_product("source-health-transitions"), do: :source_health_transitions
  defp normalize_product(:source_watermark), do: :source_watermark_events
  defp normalize_product("source_watermark"), do: :source_watermark_events
  defp normalize_product("source-watermark"), do: :source_watermark_events
  defp normalize_product(:source_watermarks), do: :source_watermark_events
  defp normalize_product("source_watermarks"), do: :source_watermark_events
  defp normalize_product("source-watermarks"), do: :source_watermark_events
  defp normalize_product(:source_watermark_events), do: :source_watermark_events
  defp normalize_product("source_watermark_events"), do: :source_watermark_events
  defp normalize_product("source-watermark-events"), do: :source_watermark_events
  defp normalize_product(:source_capability), do: :source_capability_postures
  defp normalize_product("source_capability"), do: :source_capability_postures
  defp normalize_product("source-capability"), do: :source_capability_postures
  defp normalize_product(:source_capabilities), do: :source_capability_postures
  defp normalize_product("source_capabilities"), do: :source_capability_postures
  defp normalize_product("source-capabilities"), do: :source_capability_postures
  defp normalize_product(:source_capability_postures), do: :source_capability_postures
  defp normalize_product("source_capability_postures"), do: :source_capability_postures
  defp normalize_product("source-capability-postures"), do: :source_capability_postures
  defp normalize_product(:telemetry_backfill), do: :telemetry_backfill_lifecycle
  defp normalize_product("telemetry_backfill"), do: :telemetry_backfill_lifecycle
  defp normalize_product("telemetry-backfill"), do: :telemetry_backfill_lifecycle
  defp normalize_product(:telemetry_backfills), do: :telemetry_backfill_lifecycle
  defp normalize_product("telemetry_backfills"), do: :telemetry_backfill_lifecycle
  defp normalize_product("telemetry-backfills"), do: :telemetry_backfill_lifecycle
  defp normalize_product(:backfill_lifecycle), do: :telemetry_backfill_lifecycle
  defp normalize_product("backfill_lifecycle"), do: :telemetry_backfill_lifecycle
  defp normalize_product("backfill-lifecycle"), do: :telemetry_backfill_lifecycle
  defp normalize_product(:telemetry_backfill_lifecycle), do: :telemetry_backfill_lifecycle
  defp normalize_product("telemetry_backfill_lifecycle"), do: :telemetry_backfill_lifecycle
  defp normalize_product("telemetry-backfill-lifecycle"), do: :telemetry_backfill_lifecycle
  defp normalize_product(:telemetry_revision), do: :telemetry_revision_decisions
  defp normalize_product("telemetry_revision"), do: :telemetry_revision_decisions
  defp normalize_product("telemetry-revision"), do: :telemetry_revision_decisions
  defp normalize_product(:telemetry_revisions), do: :telemetry_revision_decisions
  defp normalize_product("telemetry_revisions"), do: :telemetry_revision_decisions
  defp normalize_product("telemetry-revisions"), do: :telemetry_revision_decisions
  defp normalize_product(:telemetry_revision_decisions), do: :telemetry_revision_decisions
  defp normalize_product("telemetry_revision_decisions"), do: :telemetry_revision_decisions
  defp normalize_product("telemetry-revision-decisions"), do: :telemetry_revision_decisions
  defp normalize_product(_value), do: nil

  def time_axis(%PlannedSourceRequest{time_context: time_context}) do
    time_context
    |> get_attr(:axis)
    |> normalize_time_axis()
  end

  defp normalize_time_axis(:occurred_at), do: :occurred_at
  defp normalize_time_axis("occurred_at"), do: :occurred_at
  defp normalize_time_axis("occurred-at"), do: :occurred_at
  defp normalize_time_axis(:generation_time), do: :generation_time
  defp normalize_time_axis("generation_time"), do: :generation_time
  defp normalize_time_axis("generation-time"), do: :generation_time
  defp normalize_time_axis(:receipt_time), do: :receipt_time
  defp normalize_time_axis("receipt_time"), do: :receipt_time
  defp normalize_time_axis("receipt-time"), do: :receipt_time
  defp normalize_time_axis(value), do: value

  def realm(%PlannedSourceRequest{data_context: data_context}, source_binding) do
    get_attr(data_context, :realm) || get_attr(source_binding, :realm)
  end

  def replay_run_id(%PlannedSourceRequest{} = request) do
    DataContext.source_value(request.data_context, request.logical_source, :replay_run_id) ||
      get_attr(request.time_context, :replay_run_id)
  end

  def dataset(source_binding), do: get_attr(source_binding, :dataset)

  def source_binding_id(%{binding: %{binding_id: binding_id}}), do: binding_id
  def source_binding_id(_source_binding), do: nil

  def data_source_id(%PlannedSourceRequest{} = request, source_binding) do
    resolved_data_source_id(source_binding) || get_attr(request.data_context, :data_source_id)
  end

  defp resolved_data_source_id(%{data_source: %{data_source_id: data_source_id}}),
    do: data_source_id

  defp resolved_data_source_id(_source_binding), do: nil

  def source_endpoint_scope_id(%PlannedSourceRequest{} = request) do
    if ScopeContext.primary_kind(request.scope_context) in [:source_endpoint, "source_endpoint"] do
      request.scope_context
      |> ScopeContext.primary_ids()
      |> List.first()
    end
  end

  defp get_attr(nil, _key), do: nil

  defp get_attr(%_struct{} = struct, key) when is_atom(key) do
    struct
    |> Map.from_struct()
    |> get_attr(key)
  end

  defp get_attr(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key)))
  end

  defp get_attr(_value, _key), do: nil

  defp stringify(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify(value) when is_binary(value), do: value
  defp stringify(value), do: inspect(value)

  defp warning(%PlannedSourceRequest{} = request, code, severity, message, details) do
    %ResolveWarning{
      code: code,
      severity: severity,
      scope: :dashboard,
      message: message,
      details: Map.put(details, :source_request_id, request.request_id),
      links: DataLinks.request_observable_links(request, source: :warning)
    }
  end
end
