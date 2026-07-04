defmodule CadenceWeb.OpsDashboardShowLive.EvidenceQuery do
  @moduledoc false

  defstruct params: %{}

  @type params :: %{optional(binary()) => binary()}
  @type t :: %__MODULE__{params: params()}
  @type row :: %{label: binary(), value: binary()}

  @field_specs [
    %{
      query_key: "selected_evidence_kind",
      event_key: "kind",
      label: "Evidence kind",
      row_group: :subject
    },
    %{
      query_key: "selected_placement",
      event_key: "placement-id",
      label: "Placement",
      row_group: :subject
    },
    %{
      query_key: "selected_widget_title",
      event_key: "widget-title",
      label: "Widget",
      row_group: :subject
    },
    %{
      query_key: "selected_observable",
      event_key: "observable-id",
      label: "Observable",
      row_group: :subject
    },
    %{
      query_key: "selected_warning_code",
      event_key: "warning-code",
      label: "Warning",
      row_group: :subject
    },
    %{
      query_key: "selected_revision_state",
      event_key: "revision-state",
      label: "Revision state",
      row_group: :detail
    },
    %{
      query_key: "selected_dependency_fingerprint",
      event_key: "dependency-fingerprint",
      label: "Revision dependency",
      row_group: :detail
    },
    %{
      query_key: "selected_source_evidence_mode",
      event_key: "source-evidence-mode",
      label: "Source evidence mode",
      row_group: :subject
    },
    %{
      query_key: "selected_source_evidence_state",
      event_key: "source-evidence-state",
      label: "Source evidence state",
      row_group: :subject
    },
    %{
      query_key: "selected_source_capability_status",
      event_key: "source-capability-status",
      label: "Source capability status",
      row_group: :subject
    },
    %{
      query_key: "selected_requested_time_axis",
      event_key: "requested-time-axis",
      label: "Requested time axis",
      row_group: :detail
    },
    %{
      query_key: "selected_executed_time_axis",
      event_key: "executed-time-axis",
      label: "Executed time axis",
      row_group: :detail
    },
    %{
      query_key: "selected_supported_time_axes",
      event_key: "supported-time-axes",
      label: "Supported time axes",
      row_group: :detail
    },
    %{
      query_key: "selected_requested_sampling",
      event_key: "requested-sampling",
      label: "Requested sampling",
      row_group: :detail
    },
    %{
      query_key: "selected_supported_sampling",
      event_key: "supported-sampling",
      label: "Supported sampling",
      row_group: :detail
    },
    %{
      query_key: "selected_requested_products",
      event_key: "requested-products",
      label: "Requested products",
      row_group: :detail
    },
    %{
      query_key: "selected_supported_products",
      event_key: "supported-products",
      label: "Supported products",
      row_group: :detail
    },
    %{
      query_key: "selected_source_capability_fallbacks",
      event_key: "source-capability-fallbacks",
      label: "Source capability fallbacks",
      row_group: :detail
    },
    %{
      query_key: "selected_source_capability_unsupported",
      event_key: "source-capability-unsupported",
      label: "Unsupported source capabilities",
      row_group: :detail
    },
    %{
      query_key: "selected_cache_evidence_layer",
      event_key: "cache-evidence-layer",
      label: "Cache evidence layer",
      row_group: :subject
    },
    %{
      query_key: "selected_cache_evidence_status",
      event_key: "cache-evidence-status",
      label: "Cache evidence status",
      row_group: :subject
    },
    %{
      query_key: "selected_cache_evidence_reasons",
      event_key: "cache-evidence-reasons",
      label: "Cache evidence reasons",
      row_group: :subject
    },
    %{
      query_key: "selected_source_request",
      event_key: "source-request-id",
      label: "Source request",
      row_group: :subject
    },
    %{
      query_key: "selected_logical_source",
      event_key: "logical-source",
      label: "Logical source",
      row_group: :subject
    },
    %{query_key: "selected_realm", event_key: "realm", label: "Realm", row_group: :detail},
    %{
      query_key: "selected_data_source",
      event_key: "data-source-id",
      label: "Data source",
      row_group: :detail
    },
    %{
      query_key: "selected_source_binding",
      event_key: "source-binding-id",
      label: "Source binding",
      row_group: :detail
    },
    %{
      query_key: "selected_time_mode",
      event_key: "time-mode",
      label: "Time mode",
      row_group: :detail
    },
    %{
      query_key: "selected_time_axis",
      event_key: "time-axis",
      label: "Time axis",
      row_group: :detail
    },
    %{
      query_key: "selected_replay_run_id",
      event_key: "replay-run-id",
      label: "Replay run",
      row_group: :detail
    },
    %{
      query_key: "selected_scope_kind",
      event_key: "scope-kind",
      label: "Scope kind",
      row_group: :detail
    },
    %{
      query_key: "selected_scope_id",
      event_key: "scope-id",
      label: "Scope",
      row_group: :detail
    },
    %{
      query_key: "selected_scope_ids",
      event_key: "scope-ids",
      label: "Scopes",
      row_group: :detail
    },
    %{
      query_key: "selected_contact_id",
      event_key: "contact-id",
      label: "Contact",
      row_group: :detail
    },
    %{
      query_key: "selected_source_endpoint_id",
      event_key: "source-endpoint-id",
      label: "Source endpoint",
      row_group: :detail
    },
    %{
      query_key: "selected_source_empty_reason",
      event_key: "source-empty-reason",
      label: "Source empty reason",
      row_group: :detail
    },
    %{
      query_key: "selected_widget_data_state",
      event_key: "data-state",
      label: "Data state",
      row_group: :detail
    },
    %{
      query_key: "selected_binding_source",
      event_key: "binding-source",
      label: "Requested source",
      row_group: :detail
    },
    %{
      query_key: "selected_binding_mode",
      event_key: "binding-mode",
      label: "Binding mode",
      row_group: :detail
    },
    %{
      query_key: "selected_observables",
      event_key: "observables",
      label: "Observables",
      row_group: :detail
    },
    %{
      query_key: "selected_sampling",
      event_key: "sampling",
      label: "Sampling",
      row_group: :detail
    },
    %{
      query_key: "selected_window_seconds",
      event_key: "window-seconds",
      label: "Window seconds",
      row_group: :detail
    },
    %{
      query_key: "selected_compare_data_view",
      event_key: "compare-data-view",
      label: "Compare data view",
      row_group: :detail
    },
    %{
      query_key: "selected_widget_warning_codes",
      event_key: "widget-warning-codes",
      label: "Widget warnings",
      row_group: :detail
    },
    %{
      query_key: "selected_dashboard_health_state",
      event_key: "dashboard-health-state",
      label: "Dashboard health",
      row_group: :subject
    },
    %{
      query_key: "selected_dashboard_health_schema",
      event_key: "dashboard-health-schema",
      label: "Health snapshot schema",
      row_group: :subject
    },
    %{
      query_key: "selected_dashboard_health_snapshot_id",
      event_key: "dashboard-health-snapshot-id",
      label: "Health snapshot",
      row_group: :subject
    },
    %{
      query_key: "selected_dashboard_health_severity",
      event_key: "dashboard-health-severity",
      label: "Health severity",
      row_group: :subject
    },
    %{
      query_key: "selected_dashboard_health_widgets",
      event_key: "dashboard-health-widgets",
      label: "Widgets",
      row_group: :detail
    },
    %{
      query_key: "selected_dashboard_health_ready",
      event_key: "dashboard-health-ready",
      label: "Ready widgets",
      row_group: :detail
    },
    %{
      query_key: "selected_dashboard_health_degraded",
      event_key: "dashboard-health-degraded",
      label: "Degraded widgets",
      row_group: :detail
    },
    %{
      query_key: "selected_dashboard_health_stale",
      event_key: "dashboard-health-stale",
      label: "Stale widgets",
      row_group: :detail
    },
    %{
      query_key: "selected_dashboard_health_blocked",
      event_key: "dashboard-health-blocked",
      label: "Blocked widgets",
      row_group: :detail
    },
    %{
      query_key: "selected_dashboard_health_affected",
      event_key: "dashboard-health-affected",
      label: "Affected widgets",
      row_group: :detail
    },
    %{
      query_key: "selected_dashboard_health_states",
      event_key: "dashboard-health-states",
      label: "Health states",
      row_group: :detail
    },
    %{
      query_key: "selected_dashboard_health_affected_placements",
      event_key: "dashboard-health-affected-placements",
      label: "Affected placements",
      row_group: :detail
    },
    %{
      query_key: "selected_dashboard_health_blocked_placements",
      event_key: "dashboard-health-blocked-placements",
      label: "Blocked placements",
      row_group: :detail
    },
    %{
      query_key: "selected_dashboard_health_stale_placements",
      event_key: "dashboard-health-stale-placements",
      label: "Stale placements",
      row_group: :detail
    },
    %{
      query_key: "selected_dashboard_health_degraded_placements",
      event_key: "dashboard-health-degraded-placements",
      label: "Degraded placements",
      row_group: :detail
    },
    %{
      query_key: "selected_source_health_event_id",
      event_key: "source-health-event-id",
      label: "Source health event",
      row_group: :detail
    },
    %{
      query_key: "selected_source_health_reason",
      event_key: "source-health-reason",
      label: "Source health reason",
      row_group: :detail
    },
    %{
      query_key: "selected_source_health_probe_kind",
      event_key: "source-health-probe-kind",
      label: "Probe kind",
      row_group: :detail
    },
    %{
      query_key: "selected_source_health_probe_message",
      event_key: "source-health-probe-message",
      label: "Probe message",
      row_group: :detail
    },
    %{
      query_key: "selected_source_health_probe_metadata",
      event_key: "source-health-probe-metadata",
      label: "Probe metadata",
      row_group: :detail
    },
    %{
      query_key: "selected_requested_realm",
      event_key: "requested-realm",
      label: "Requested realm",
      row_group: :detail
    },
    %{
      query_key: "selected_requested_data_view",
      event_key: "requested-data-view",
      label: "Requested data view",
      row_group: :detail
    },
    %{
      query_key: "selected_requested_data_source",
      event_key: "requested-data-source-id",
      label: "Requested data source",
      row_group: :detail
    },
    %{
      query_key: "selected_requested_source_binding",
      event_key: "requested-source-binding-id",
      label: "Requested source binding",
      row_group: :detail
    },
    %{
      query_key: "selected_requested_dataset",
      event_key: "requested-dataset",
      label: "Requested dataset",
      row_group: :detail
    },
    %{
      query_key: "selected_requested_validity_state",
      event_key: "requested-validity-state",
      label: "Requested validity",
      row_group: :detail
    }
  ]

  @subject_preference [
    "selected_dashboard_health_state",
    "selected_widget_title",
    "selected_warning_code",
    "selected_observable",
    "selected_source_request",
    "selected_logical_source",
    "selected_evidence_kind"
  ]

  @source_context_event_keys [
    "source-request-id",
    "logical-source",
    "realm",
    "data-source-id",
    "source-binding-id",
    "scope-kind",
    "scope-id",
    "scope-ids",
    "contact-id",
    "source-endpoint-id",
    "source-health-event-id",
    "source-health-reason",
    "source-health-probe-kind",
    "source-health-probe-message",
    "source-health-probe-metadata"
  ]

  @source_context_query_keys [
    "selected_source_request",
    "selected_logical_source",
    "selected_realm",
    "selected_data_source",
    "selected_source_binding"
  ]

  @cache_context_event_keys [
    "source-evidence-state",
    "cache-evidence-layer",
    "cache-evidence-status",
    "cache-evidence-reasons"
  ]

  @capability_context_event_keys [
    "source-capability-status",
    "requested-time-axis",
    "executed-time-axis",
    "supported-time-axes",
    "requested-sampling",
    "supported-sampling",
    "requested-products",
    "supported-products",
    "source-capability-fallbacks",
    "source-capability-unsupported"
  ]

  @cache_context_query_keys [
    "selected_source_evidence_state",
    "selected_cache_evidence_layer",
    "selected_cache_evidence_status",
    "selected_cache_evidence_reasons"
  ]

  @capability_context_query_keys [
    "selected_source_capability_status",
    "selected_requested_time_axis",
    "selected_executed_time_axis",
    "selected_supported_time_axes",
    "selected_requested_sampling",
    "selected_supported_sampling",
    "selected_requested_products",
    "selected_supported_products",
    "selected_source_capability_fallbacks",
    "selected_source_capability_unsupported"
  ]

  @source_request_detail_event_keys [
    "time-mode",
    "time-axis",
    "replay-run-id",
    "scope-kind",
    "scope-id",
    "scope-ids",
    "contact-id",
    "source-endpoint-id",
    "source-empty-reason",
    "source-health-event-id",
    "source-health-reason",
    "source-health-probe-kind",
    "source-health-probe-message",
    "source-health-probe-metadata",
    "source-evidence-state",
    "cache-evidence-layer",
    "cache-evidence-status",
    "cache-evidence-reasons",
    "source-capability-status",
    "requested-time-axis",
    "executed-time-axis",
    "supported-time-axes",
    "requested-sampling",
    "supported-sampling",
    "requested-products",
    "supported-products",
    "source-capability-fallbacks",
    "source-capability-unsupported",
    "requested-realm",
    "requested-data-view",
    "requested-data-source-id",
    "requested-source-binding-id",
    "requested-dataset",
    "requested-validity-state"
  ]

  @source_identity_specs [
    %{label: "Logical source", event_key: "logical-source", source_key: :logical_source},
    %{label: "Realm", event_key: "realm", source_key: :realm},
    %{label: "Freshness", source_key: :state},
    %{label: "Source request", event_key: "source-request-id", source_key: :request_id},
    %{label: "Data source", event_key: "data-source-id", source_key: :data_source_id},
    %{label: "Source binding", event_key: "source-binding-id", source_key: :source_binding_id}
  ]

  @event_attr_names Map.new(@field_specs, fn spec ->
                      {spec.event_key, "phx-value-#{spec.event_key}"}
                    end)

  @spec from_params(map(), atom() | nil) :: t() | nil
  def from_params(params, :data_link) when is_map(params), do: nil

  def from_params(params, panel_query)
      when is_map(params) and panel_query not in [nil, :evidence],
      do: nil

  def from_params(params, _panel_query) when is_map(params) do
    params
    |> build_query(:query_key)
    |> case do
      query when map_size(query) == 0 -> nil
      %{"selected_evidence_kind" => _kind} = query -> new(query)
      _query -> nil
    end
  end

  def from_params(_params, _panel_query), do: nil

  @spec from_event_params(map()) :: t()
  def from_event_params(params) when is_map(params),
    do: params |> build_query(:event_key) |> normalize_query() |> new()

  def from_event_params(_params), do: new(%{})

  @spec new(params() | t() | nil) :: t()
  def new(%__MODULE__{} = query), do: query
  def new(params) when is_map(params), do: %__MODULE__{params: compact_flat(params)}
  def new(_params), do: %__MODULE__{}

  @spec to_params(t() | params() | nil) :: params()
  def to_params(%__MODULE__{params: params}), do: params
  def to_params(params) when is_map(params), do: compact_flat(params)
  def to_params(_query), do: %{}

  @spec phx_value_attrs(map()) :: map()
  def phx_value_attrs(params) when is_map(params) do
    params
    |> Enum.flat_map(fn {key, value} ->
      case Map.get(@event_attr_names, key) do
        nil -> []
        attr_name -> [{attr_name, value}]
      end
    end)
    |> Map.new()
    |> compact_flat()
  end

  def phx_value_attrs(_params), do: %{}

  @spec to_event_params(t()) :: map()
  def to_event_params(query) do
    query = to_params(query)

    @field_specs
    |> Map.new(fn %{query_key: query_key, event_key: event_key} ->
      {event_key, Map.get(query, query_key)}
    end)
    |> compact_flat()
  end

  @spec clear_query() :: map()
  def clear_query do
    Map.new(@field_specs, fn %{query_key: query_key} -> {query_key, nil} end)
  end

  @spec query?(term()) :: boolean()
  def query?(query), do: value(query, "selected_evidence_kind") != nil

  @spec value(term(), binary()) :: term()
  def value(query, key), do: query |> to_params() |> Map.get(key)

  @spec subject(t()) :: binary()
  def subject(query) do
    query = to_params(query)

    Enum.find_value(@subject_preference, fn key -> Map.get(query, key) end) || "evidence"
  end

  @spec subject_rows(t(), (term() -> binary() | nil)) :: [row()]
  def subject_rows(query, formatter), do: rows(query, :subject, formatter)

  @spec detail_rows(t(), (term() -> binary() | nil)) :: [row()]
  def detail_rows(query, formatter), do: rows(query, :detail, formatter)

  @spec source_request_detail_rows(map(), (term() -> binary() | nil)) :: [row()]
  def source_request_detail_rows(params, formatter),
    do: event_rows(params, @source_request_detail_event_keys, formatter)

  @spec source_identity_rows_from_event_params(map(), (term() -> binary() | nil)) :: [row()]
  def source_identity_rows_from_event_params(params, formatter) do
    source_identity_rows(params, :event_key, formatter, include_freshness?: false)
  end

  @spec source_identity_rows_from_source(map(), (term() -> binary() | nil)) :: [row()]
  def source_identity_rows_from_source(source, formatter) do
    source_identity_rows(source, :source_key, formatter, include_freshness?: true)
  end

  @spec source_subject_from_event_params(map()) :: binary()
  def source_subject_from_event_params(params) when is_map(params) do
    Map.get(params, "source-request-id") ||
      Map.get(params, "logical-source") ||
      "source"
  end

  def source_subject_from_event_params(_params), do: "source"

  @spec source_context_event_query?(map()) :: boolean()
  def source_context_event_query?(params) when is_map(params) do
    has_any_event_key?(params, @source_context_event_keys) and
      (has_any_event_key?(params, @cache_context_event_keys) or
         has_any_event_key?(params, @capability_context_event_keys))
  end

  def source_context_event_query?(_params), do: false

  @spec source_context_query?(t()) :: boolean()
  def source_context_query?(query) do
    query = to_params(query)

    has_any_query_key?(query, @source_context_query_keys) and
      (has_any_query_key?(query, @cache_context_query_keys) or
         has_any_query_key?(query, @capability_context_query_keys))
  end

  defp build_query(params, source_key) do
    @field_specs
    |> Map.new(fn spec ->
      {spec.query_key, text_param(Map.get(params, Map.fetch!(spec, source_key)))}
    end)
    |> compact_flat()
  end

  defp normalize_query(
         %{
           "selected_scope_kind" => "source_endpoint",
           "selected_scope_id" => source_endpoint_id
         } = query
       ) do
    Map.update(query, "selected_source_endpoint_id", source_endpoint_id, fn
      value when value in [nil, "", "nil"] -> source_endpoint_id
      value -> value
    end)
  end

  defp normalize_query(query), do: query

  defp rows(query, row_group, formatter) when is_function(formatter, 1) do
    query = to_params(query)

    @field_specs
    |> Enum.filter(&(&1.row_group == row_group))
    |> Enum.map(fn %{query_key: query_key, label: label} ->
      detail_row(label, Map.get(query, query_key), formatter)
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp rows(_query, _row_group, _formatter), do: []

  defp event_rows(params, event_keys, formatter)
       when is_map(params) and is_list(event_keys) and is_function(formatter, 1) do
    event_keys
    |> Enum.map(fn event_key ->
      case Enum.find(@field_specs, &(&1.event_key == event_key)) do
        nil -> nil
        spec -> detail_row(spec.label, Map.get(params, event_key), formatter)
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp event_rows(_params, _event_keys, _formatter), do: []

  defp source_identity_rows(source, key_name, formatter, opts)
       when is_map(source) and is_function(formatter, 1) do
    include_freshness? = Keyword.fetch!(opts, :include_freshness?)

    @source_identity_specs
    |> Enum.reject(fn spec -> spec.label == "Freshness" and not include_freshness? end)
    |> Enum.map(fn spec ->
      detail_row(spec.label, Map.get(source, Map.fetch!(spec, key_name)), formatter)
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp source_identity_rows(_source, _key_name, _formatter, _opts), do: []

  defp detail_row(_label, value, _formatter) when value in [nil, ""], do: nil

  defp detail_row(label, value, formatter) do
    case formatter.(value) do
      value when value in [nil, ""] -> nil
      value -> %{label: label, value: value}
    end
  end

  defp compact_flat(map) when is_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp text_param(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp text_param(_value), do: nil

  defp has_any_event_key?(params, event_keys) do
    Enum.any?(event_keys, fn event_key -> present?(Map.get(params, event_key)) end)
  end

  defp has_any_query_key?(query, query_keys) do
    Enum.any?(query_keys, fn query_key -> present?(Map.get(query, query_key)) end)
  end

  defp present?(value), do: value not in [nil, ""]
end
