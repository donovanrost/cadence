defmodule CadenceWeb.OpsDataSourcesLive.SourceFocus do
  @moduledoc """
  URL focus parsing and source-inventory matching for the data sources page.
  """

  alias Cadence.Dashboards.{DataBinding, DataSource}

  @spec default() :: map()
  def default do
    %{
      state: "none",
      data_source_id: nil,
      source_binding_id: nil,
      logical_source: nil,
      realm: nil,
      scope_kind: nil,
      scope_id: nil,
      contact_id: nil,
      selected_target: nil,
      selected_id: nil,
      transport_id: nil,
      source_endpoint_id: nil,
      ground_station_id: nil,
      link_id: nil,
      source_empty_reason: nil,
      requested_sampling: nil,
      supported_sampling: nil,
      requested_products: nil,
      requested_source_products: nil,
      supported_products: nil,
      requested_product_families: nil,
      supported_product_families: nil,
      requested_value_kinds: nil,
      supported_value_kinds: nil,
      requested_shapes: nil,
      supported_shapes: nil,
      requested_time_axes: nil,
      supported_time_axes: nil,
      source_dashboard_id: nil,
      source_return_panel: nil,
      source_return_activity_filter: nil,
      source_return_activity_event: nil,
      selected_evidence_kind: nil,
      selected_source_evidence_mode: nil,
      selected_source_evidence_state: nil,
      matched_data_source_id: nil,
      matched_source_binding_id: nil
    }
  end

  @spec from_params(map()) :: map()
  def from_params(params) when is_map(params) do
    focus = %{
      default()
      | state: "pending",
        data_source_id: optional_text(Map.get(params, "data_source_id")),
        source_binding_id: optional_text(Map.get(params, "source_binding_id")),
        logical_source: optional_text(Map.get(params, "logical_source")),
        realm: optional_text(Map.get(params, "realm")),
        scope_kind: optional_text(Map.get(params, "scope_kind")),
        scope_id: optional_text(Map.get(params, "scope_id")),
        contact_id: optional_text(Map.get(params, "contact_id")),
        selected_target: optional_text(Map.get(params, "selected_target")),
        selected_id: optional_text(Map.get(params, "selected_id")),
        transport_id: optional_text(Map.get(params, "transport_id")),
        source_endpoint_id: optional_text(Map.get(params, "source_endpoint_id")),
        ground_station_id: optional_text(Map.get(params, "ground_station_id")),
        link_id: optional_text(Map.get(params, "link_id")),
        source_empty_reason: optional_text(Map.get(params, "source_empty_reason")),
        requested_sampling: optional_text(Map.get(params, "requested_sampling")),
        supported_sampling: optional_text(Map.get(params, "supported_sampling")),
        requested_products: optional_text(Map.get(params, "requested_products")),
        requested_source_products: optional_text(Map.get(params, "requested_source_products")),
        supported_products: optional_text(Map.get(params, "supported_products")),
        requested_product_families: optional_text(Map.get(params, "requested_product_families")),
        supported_product_families: optional_text(Map.get(params, "supported_product_families")),
        requested_value_kinds: optional_text(Map.get(params, "requested_value_kinds")),
        supported_value_kinds: optional_text(Map.get(params, "supported_value_kinds")),
        requested_shapes: optional_text(Map.get(params, "requested_shapes")),
        supported_shapes: optional_text(Map.get(params, "supported_shapes")),
        requested_time_axes: optional_text(Map.get(params, "requested_time_axes")),
        supported_time_axes: optional_text(Map.get(params, "supported_time_axes")),
        source_dashboard_id: optional_text(Map.get(params, "source_dashboard_id")),
        source_return_panel: optional_text(Map.get(params, "source_return_panel")),
        source_return_activity_filter:
          optional_text(Map.get(params, "source_return_activity_filter")),
        source_return_activity_event:
          optional_text(Map.get(params, "source_return_activity_event")),
        selected_evidence_kind: optional_text(Map.get(params, "selected_evidence_kind")),
        selected_source_evidence_mode:
          optional_text(Map.get(params, "selected_source_evidence_mode")),
        selected_source_evidence_state:
          optional_text(Map.get(params, "selected_source_evidence_state"))
    }

    if requested?(focus), do: focus, else: default()
  end

  @spec resolve(map(), [DataSource.t()], [DataBinding.t()]) :: map()
  def resolve(%{state: "none"} = focus, _sources, _bindings), do: focus

  def resolve(focus, sources, bindings) when is_list(sources) and is_list(bindings) do
    source_by_id = Map.new(sources, &{&1.data_source_id, &1})
    requested_source = requested_source(focus, source_by_id)
    requested_binding = requested_binding(focus, bindings)
    context_binding = context_binding(focus, bindings)
    matched_binding = first_present(requested_binding, context_binding)

    matched_source =
      first_present(requested_source, binding_source(matched_binding, source_by_id))

    if matched?(
         focus,
         requested_source,
         requested_binding,
         matched_source,
         matched_binding
       ) do
      %{
        focus
        | state: "matched",
          matched_data_source_id: matched_data_source_id(matched_source),
          matched_source_binding_id: matched_source_binding_id(matched_binding)
      }
    else
      %{focus | state: "missing", matched_data_source_id: nil, matched_source_binding_id: nil}
    end
  end

  @spec source_focused?(map(), map()) :: boolean()
  def source_focused?(%{state: "matched"} = focus, %{data_source_id: _data_source_id} = source),
    do: source.data_source_id == focus.matched_data_source_id

  def source_focused?(_focus, _source), do: false

  @spec binding_focused?(map(), map()) :: boolean()
  def binding_focused?(%{state: "matched"} = focus, %{binding: %DataBinding{} = binding}),
    do: binding.binding_id == focus.matched_source_binding_id

  def binding_focused?(_focus, _row), do: false

  @spec icon(map()) :: binary()
  def icon(%{state: "matched"}), do: "hero-arrow-top-right-on-square"
  def icon(%{state: "missing"}), do: "hero-exclamation-triangle"
  def icon(_focus), do: "hero-information-circle"

  @spec title(map()) :: binary()
  def title(%{state: "matched"}), do: "Source evidence matched"
  def title(%{state: "missing"}), do: "Source evidence no longer matches current inventory"
  def title(_focus), do: "Source evidence"

  @spec detail(map()) :: binary()
  def detail(focus) do
    [
      {"data_source_id", focus.data_source_id},
      {"source_binding_id", focus.source_binding_id},
      {"logical_source", focus.logical_source},
      {"realm", focus.realm},
      {"scope_kind", focus.scope_kind},
      {"scope_id", focus.scope_id},
      {"contact_id", focus.contact_id},
      {"selected_target", focus.selected_target},
      {"selected_id", focus.selected_id},
      {"transport_id", focus.transport_id},
      {"source_endpoint_id", focus.source_endpoint_id},
      {"ground_station_id", focus.ground_station_id},
      {"link_id", focus.link_id},
      {"source_empty_reason", focus.source_empty_reason},
      {"requested_sampling", focus.requested_sampling},
      {"supported_sampling", focus.supported_sampling},
      {"requested_products", focus.requested_products},
      {"requested_source_products", focus.requested_source_products},
      {"supported_products", focus.supported_products},
      {"requested_product_families", focus.requested_product_families},
      {"supported_product_families", focus.supported_product_families},
      {"requested_value_kinds", focus.requested_value_kinds},
      {"supported_value_kinds", focus.supported_value_kinds},
      {"requested_shapes", focus.requested_shapes},
      {"supported_shapes", focus.supported_shapes},
      {"requested_time_axes", focus.requested_time_axes},
      {"supported_time_axes", focus.supported_time_axes},
      {"selected_evidence_kind", focus.selected_evidence_kind},
      {"selected_source_evidence_mode", focus.selected_source_evidence_mode},
      {"selected_source_evidence_state", focus.selected_source_evidence_state},
      {"source_dashboard_id", focus.source_dashboard_id}
    ]
    |> Enum.reject(fn {_label, value} -> is_nil(value) end)
    |> Enum.map_join(" ", fn {label, value} -> "#{label}=#{value}" end)
  end

  @spec return_panel(map()) :: binary()
  def return_panel(%{source_return_panel: panel}) when is_binary(panel) and panel != "",
    do: panel

  def return_panel(_focus), do: "versions"

  @spec return_activity_filter(map()) :: binary()
  def return_activity_filter(%{source_return_activity_filter: activity_filter})
      when is_binary(activity_filter) and activity_filter != "",
      do: activity_filter

  def return_activity_filter(_focus), do: "publish_readiness"

  @spec return_activity_event(map()) :: binary() | nil
  def return_activity_event(%{source_return_activity_event: activity_event})
      when is_binary(activity_event) and activity_event != "",
      do: activity_event

  def return_activity_event(_focus), do: nil

  @spec return_refresh_readiness(map()) :: binary() | nil
  def return_refresh_readiness(%{source_return_activity_filter: "publish_readiness"}),
    do: "source_return"

  def return_refresh_readiness(%{source_return_activity_filter: nil}), do: "source_return"
  def return_refresh_readiness(_focus), do: nil

  defp requested?(focus) do
    Enum.any?(
      [
        focus.data_source_id,
        focus.source_binding_id,
        focus.logical_source,
        focus.realm,
        focus.scope_kind,
        focus.scope_id,
        focus.contact_id,
        focus.selected_target,
        focus.selected_id,
        focus.transport_id,
        focus.source_endpoint_id,
        focus.ground_station_id,
        focus.link_id,
        focus.source_empty_reason,
        focus.requested_sampling,
        focus.supported_sampling,
        focus.requested_products,
        focus.requested_source_products,
        focus.supported_products,
        focus.requested_product_families,
        focus.supported_product_families,
        focus.requested_value_kinds,
        focus.supported_value_kinds,
        focus.requested_shapes,
        focus.supported_shapes,
        focus.requested_time_axes,
        focus.supported_time_axes,
        focus.selected_evidence_kind,
        focus.selected_source_evidence_mode,
        focus.selected_source_evidence_state
      ],
      &is_binary/1
    )
  end

  defp requested_source(%{data_source_id: nil}, _source_by_id), do: nil
  defp requested_source(focus, source_by_id), do: Map.get(source_by_id, focus.data_source_id)

  defp requested_binding(%{source_binding_id: nil}, _bindings), do: nil
  defp requested_binding(focus, bindings), do: find_binding(bindings, focus.source_binding_id)

  defp context_binding(focus, bindings),
    do: Enum.find(bindings, &binding_matches_focus?(&1, focus))

  defp binding_matches_focus?(%DataBinding{} = binding, focus) do
    binding_matches_context?(binding, focus) and binding_matches_source?(binding, focus)
  end

  defp binding_matches_source?(_binding, %{data_source_id: nil}), do: true

  defp binding_matches_source?(%DataBinding{} = binding, focus),
    do: binding.data_source_id == focus.data_source_id

  defp binding_source(nil, _source_by_id), do: nil

  defp binding_source(%DataBinding{} = binding, source_by_id),
    do: Map.get(source_by_id, binding.data_source_id)

  defp first_present(nil, fallback), do: fallback
  defp first_present(value, _fallback), do: value

  defp matched_data_source_id(nil), do: nil
  defp matched_data_source_id(%DataSource{} = source), do: source.data_source_id

  defp matched_source_binding_id(nil), do: nil
  defp matched_source_binding_id(%DataBinding{} = binding), do: binding.binding_id

  defp matched?(focus, requested_source, requested_binding, matched_source, matched_binding) do
    requested?(focus) and
      requested_source_found?(focus, requested_source) and
      requested_binding_found?(focus, requested_binding) and
      binding_source_consistent?(focus, matched_binding) and
      context_consistent?(focus, matched_binding) and
      source_or_binding_found?(matched_source, matched_binding)
  end

  defp source_or_binding_found?(nil, nil), do: false
  defp source_or_binding_found?(_source, _binding), do: true

  defp requested_source_found?(%{data_source_id: nil}, _requested_source), do: true
  defp requested_source_found?(_focus, %DataSource{}), do: true
  defp requested_source_found?(_focus, _requested_source), do: false

  defp requested_binding_found?(%{source_binding_id: nil}, _requested_binding), do: true
  defp requested_binding_found?(_focus, %DataBinding{}), do: true
  defp requested_binding_found?(_focus, _requested_binding), do: false

  defp binding_source_consistent?(%{data_source_id: nil}, _binding), do: true
  defp binding_source_consistent?(_focus, nil), do: true

  defp binding_source_consistent?(focus, %DataBinding{} = binding),
    do: binding.data_source_id == focus.data_source_id

  defp context_consistent?(%{logical_source: nil, realm: nil}, _binding), do: true
  defp context_consistent?(_focus, nil), do: false

  defp context_consistent?(focus, %DataBinding{} = binding),
    do: binding_matches_context?(binding, focus)

  defp binding_matches_context?(%DataBinding{} = binding, focus) do
    (is_nil(focus.logical_source) or text(binding.logical_source) == focus.logical_source) and
      (is_nil(focus.realm) or text(binding.realm) == focus.realm)
  end

  defp find_binding(bindings, binding_id) do
    Enum.find(bindings, &(&1.binding_id == binding_id))
  end

  defp optional_text(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp optional_text(_value), do: nil

  defp text(nil), do: "none"
  defp text(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp text(value) when is_atom(value), do: Atom.to_string(value)
  defp text(value) when is_binary(value), do: value
  defp text(value), do: to_string(value)
end
