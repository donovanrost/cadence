defmodule CadenceWeb.OpsDashboardShowLive.WidgetFormPresentation do
  @moduledoc false

  alias Cadence.Dashboards.{
    OperationalObservable,
    Placement,
    PlacementEditor,
    ScopeContext,
    WidgetFrameContract
  }

  alias Cadence.ExtensionCatalog
  alias Phoenix.HTML.Form

  @point_widget_types [
    "value_tile",
    "time_series",
    "status_matrix",
    "data_table",
    "state_timeline"
  ]

  @multi_point_widget_types ["status_matrix", "data_table"]

  @mode_options [
    {"Follow dashboard context", "context"},
    {"Pin current dashboard context", "scope"},
    {"Pin to one spacecraft", "fixed"}
  ]

  @repeat_option {"Repeat for selected resources", "repeat"}

  @window_options [
    {"5 minutes", "300"},
    {"15 minutes", "900"},
    {"1 hour", "3600"},
    {"1 minute", "60"}
  ]

  @scope_kinds [
    :mission,
    :spacecraft,
    :contact,
    :ground_station,
    :source_endpoint,
    :transport,
    :link
  ]

  def widget_form_defaults, do: PlacementEditor.form_defaults()

  def placement_to_form_params(%Placement{} = placement),
    do: PlacementEditor.to_form_params(placement)

  def filter_points(points, query) when query in [nil, ""], do: Enum.take(points, 50)

  def filter_points(points, query) do
    downcased = String.downcase(query)

    points
    |> Enum.filter(fn point ->
      String.contains?(String.downcase(point.point_id), downcased) or
        String.contains?(String.downcase(point.description || ""), downcased)
    end)
    |> Enum.take(50)
  end

  def selected_point(_points, nil), do: nil
  def selected_point(points, point_id), do: Enum.find(points, &(&1.point_id == point_id))

  def selected_points(points, point_ids) when is_list(point_ids) do
    points_by_id = Map.new(points, &{&1.point_id, &1})

    point_ids
    |> Enum.map(&Map.get(points_by_id, &1))
    |> Enum.reject(&is_nil/1)
  end

  def selected_points(_points, _point_ids), do: []

  def filter_operational_observables(observables, query, widget_type \\ nil)

  def filter_operational_observables(observables, query, widget_type) when query in [nil, ""] do
    observables
    |> filter_operational_observables_for_widget(widget_type)
    |> Enum.take(50)
  end

  def filter_operational_observables(observables, query, widget_type) do
    downcased = String.downcase(query)

    observables
    |> filter_operational_observables_for_widget(widget_type)
    |> Enum.filter(fn observable ->
      String.contains?(String.downcase(observable.observable_id), downcased) or
        String.contains?(String.downcase(observable.name || ""), downcased) or
        String.contains?(String.downcase(observable.description || ""), downcased)
    end)
    |> Enum.take(50)
  end

  def selected_operational_observables(observables, observable_ids, widget_type \\ nil)

  def selected_operational_observables(observables, observable_ids, widget_type)
      when is_list(observable_ids) do
    observables_by_id =
      observables
      |> filter_operational_observables_for_widget(widget_type)
      |> Map.new(&{&1.observable_id, &1})

    observable_ids
    |> Enum.map(&Map.get(observables_by_id, &1))
    |> Enum.reject(&is_nil/1)
  end

  def selected_operational_observables(_observables, _observable_ids, _widget_type), do: []

  def operational_observable_picker_groups(observables, form) when is_list(observables) do
    if operational_metric_history_widget?(form) do
      metric_history_picker_groups(observables)
    else
      [
        %{
          id: "operational_observables",
          label: "Operational observables",
          source_product_value: "",
          product_family_value: "",
          observables: observables
        }
      ]
    end
  end

  def operational_observable_picker_groups(_observables, _form), do: []

  def operational_observable_source_product(observable) do
    observable
    |> observable_id()
    |> metric_history_contract_for_observable()
    |> case do
      %{product: product} -> product
      _contract -> nil
    end
  end

  def operational_observable_product_family(observable) do
    observable
    |> observable_id()
    |> metric_history_contract_for_observable()
    |> case do
      %{product_family: product_family} -> product_family
      _contract -> nil
    end
  end

  def operational_observable_source_product_value(observable),
    do: atom_value(operational_observable_source_product(observable))

  def operational_observable_product_family_value(observable),
    do: atom_value(operational_observable_product_family(observable))

  def point_widget?(form), do: form_value(form, :type) in @point_widget_types

  def multi_point_widget?(form) do
    form_value(form, :type) in @multi_point_widget_types or
      (form_value(form, :type) == "state_timeline" and operational_observable_widget?(form))
  end

  def operational_observable_widget?(form) do
    binding_source_value(form) == "operational_observables" and
      :operational_observables in widget_supported_sources(form)
  end

  def point_picker_legend(form) do
    if multi_point_widget?(form), do: "Telemetry Points", else: "Telemetry Point"
  end

  def selected_point?(form, point, selected_points, selected_point) do
    if multi_point_widget?(form) do
      Enum.any?(selected_points, &(&1.point_id == point.point_id))
    else
      selected_point != nil and selected_point.point_id == point.point_id
    end
  end

  def point_button_class(form, point, selected_points, selected_point) do
    selected? = selected_point?(form, point, selected_points, selected_point)

    [
      "flex w-full items-start gap-1.5 rounded px-2 py-1 text-left text-sm hover:bg-base-300",
      selected? && "bg-primary/10 text-primary"
    ]
  end

  def selected_operational_observable?(observable, selected_observables) do
    Enum.any?(selected_observables, &(&1.observable_id == observable.observable_id))
  end

  def operational_observable_button_class(observable, selected_observables, scope_context \\ nil) do
    selected? = selected_operational_observable?(observable, selected_observables)

    selectable? =
      operational_observable_selectable?(observable, selected_observables, scope_context)

    [
      "flex w-full items-start gap-1.5 rounded px-2 py-1 text-left text-sm hover:bg-base-300",
      selected? && "bg-primary/10 text-primary",
      not selectable? && "cursor-not-allowed opacity-45 hover:bg-transparent"
    ]
  end

  def operational_observable_selectable?(observable, selected_observables, scope_context) do
    selected_operational_observable?(observable, selected_observables) or
      operational_observable_scope_supported?(observable, scope_context)
  end

  def operational_observable_scope_supported?(observable, scope_context) do
    scope_kind =
      scope_context
      |> ScopeContext.primary_kind()
      |> normalize_scope_kind()

    scopes = operational_observable_scopes(observable)

    is_nil(scope_kind) or scopes == [] or scope_kind in scopes
  end

  def unsupported_selected_operational_observable_ids(selected_observables, scope_context)
      when is_list(selected_observables) do
    selected_observables
    |> Enum.reject(&operational_observable_scope_supported?(&1, scope_context))
    |> Enum.map(& &1.observable_id)
  end

  def unsupported_selected_operational_observable_ids(_selected_observables, _scope_context),
    do: []

  def selected_operational_observable_scope_warning(selected_observables, scope_context) do
    case unsupported_selected_operational_observable_ids(selected_observables, scope_context) do
      [] ->
        nil

      [observable_id] ->
        "Current context does not support #{observable_id}."

      observable_ids ->
        "Current context does not support #{Enum.join(observable_ids, ", ")}."
    end
  end

  def operational_observable_scope_values(observable) do
    observable
    |> operational_observable_scopes()
    |> Enum.map_join(" ", &Atom.to_string/1)
  end

  def operational_observable_scope_badges(observable) do
    observable
    |> operational_observable_scopes()
    |> Enum.map(&scope_label/1)
  end

  def operational_observable_scope_title(observable) do
    case operational_observable_scope_badges(observable) do
      [] -> nil
      badges -> "Scopes: #{Enum.join(badges, ", ")}"
    end
  end

  def form_value(form, field), do: Form.input_value(form, field)

  def type_options do
    Enum.map(ExtensionCatalog.widget_types(), &{&1.form_label, &1.form_value})
  end

  def non_point_widget_help(form) do
    case form_value(form, :type) do
      "event_timeline" ->
        "Event timelines render mission, contact, source, and data-management events in the active dashboard time and scope. No point binding required."

      _other ->
        "Constellation health rolls every spacecraft up to its worst current limit state. No point binding required."
    end
  end

  def mode_options, do: @mode_options

  def mode_options(form) do
    options =
      if operational_observable_widget?(form) do
        Enum.reject(@mode_options, fn {_label, value} -> value == "fixed" end)
      else
        @mode_options
      end

    if repeat_supported?(form), do: options ++ [@repeat_option], else: options
  end

  def repeat_supported?(form) do
    with widget_type_id when is_binary(widget_type_id) <- form_widget_type_id(form),
         {:ok, widget_type} <- ExtensionCatalog.fetch_widget_type(widget_type_id, :latest) do
      :repeat in widget_type.binding_schema.scope_modes
    else
      _missing -> false
    end
  end

  def repeat_over_options do
    [
      {"Spacecraft", "spacecraft"},
      {"Contacts", "contact"},
      {"Ground stations", "ground_station"},
      {"Transports", "transport"},
      {"Links", "link"}
    ]
  end

  def repeat_layout_options do
    [{"Wrap grid", "wrap_grid"}, {"Single row", "row"}, {"Single column", "column"}]
  end

  def repeat_max_options, do: Enum.map([4, 8, 12, 16, 24], &{"Up to #{&1}", to_string(&1)})

  def legend_mode_options,
    do: [{"Auto", "auto"}, {"Always", "always"}, {"Hidden", "hidden"}]

  def line_width_options,
    do: [{"Thin", "thin"}, {"Normal", "normal"}, {"Bold", "bold"}]

  def fill_opacity_options,
    do: [{"None", "0"}, {"Subtle", "8"}, {"Medium", "16"}, {"Strong", "30"}]

  def axis_mode_options,
    do: [{"Group by engineering unit", "unit"}, {"Shared value axis", "shared"}]

  def scope_override_kind(scope_context) do
    scope_context
    |> ScopeContext.from_map()
    |> scope_override_selector()
    |> elem(0)
  end

  def scope_override_id(scope_context) do
    scope_context
    |> ScopeContext.from_map()
    |> scope_override_selector()
    |> elem(1)
  end

  def scope_override_summary(scope_context) do
    case scope_override_selector(ScopeContext.from_map(scope_context)) do
      {nil, nil} ->
        "Choose a dashboard context before pinning this widget."

      {kind, id} ->
        "Pins this widget to #{scope_label(kind)} #{id}."
    end
  end

  def scope_override_available?(scope_context) do
    scope_override_kind(scope_context) != nil and scope_override_id(scope_context) != nil
  end

  def binding_source_select?(form), do: length(binding_source_options(form)) > 1

  def binding_source_options(form) do
    form
    |> widget_supported_sources()
    |> Enum.flat_map(&binding_source_option/1)
  end

  def widget_supported_sources(form) do
    form
    |> form_widget_type_id()
    |> fetch_widget_supported_sources()
  end

  def binding_source_value(form) do
    case form_value(form, :binding_source) do
      nil -> default_binding_source_value(form)
      "" -> default_binding_source_value(form)
      value -> value
    end
  end

  def spacecraft_options(spacecraft) do
    [{"Select a spacecraft", ""}] ++
      Enum.map(spacecraft, &{&1.display_name, &1.spacecraft_id})
  end

  def precision_options, do: Enum.map(0..6, &{"#{&1} decimals", "#{&1}"})

  def window_options, do: @window_options

  defp fetch_widget_supported_sources(nil), do: [:telemetry]

  defp fetch_widget_supported_sources(widget_type_id) do
    case ExtensionCatalog.fetch_widget_type(widget_type_id, :latest) do
      {:ok, widget_type} ->
        widget_type
        |> WidgetFrameContract.primary_supported_sources()
        |> ordered_binding_sources()

      {:error, _reason} ->
        [:telemetry]
    end
  end

  defp ordered_binding_sources(sources) do
    Enum.filter([:telemetry, :limits, :operational_observables, :events], &(&1 in sources))
  end

  defp binding_source_option(:telemetry), do: [{"Telemetry points", "telemetry"}]
  defp binding_source_option(:limits), do: [{"Telemetry limit history", "limits"}]

  defp binding_source_option(:operational_observables),
    do: [{"Operational observables", "operational_observables"}]

  defp binding_source_option(:events), do: [{"Events", "events"}]

  defp binding_source_option(_source), do: []

  defp default_binding_source_value(form) do
    sources = widget_supported_sources(form)

    cond do
      :telemetry in sources -> "telemetry"
      :limits in sources -> "limits"
      :operational_observables in sources -> "operational_observables"
      :events in sources -> "events"
      true -> "telemetry"
    end
  end

  defp form_widget_type_id(form), do: widget_type_id_for_form_type(form_value(form, :type))

  defp widget_type_id_for_form_type(form_value) when is_binary(form_value) do
    case Enum.find(ExtensionCatalog.widget_types(), &(&1.form_value == form_value)) do
      nil -> nil
      widget_type -> widget_type.widget_type_id
    end
  end

  defp widget_type_id_for_form_type(_form_value), do: nil

  defp filter_operational_observables_for_widget(observables, widget_type) do
    case widget_type_id_for_form_type(widget_type) do
      nil ->
        observables

      widget_type_id ->
        case ExtensionCatalog.fetch_widget_type(widget_type_id, :latest) do
          {:ok, widget_type} ->
            Enum.filter(
              observables,
              &WidgetFrameContract.operational_observable_supported?(widget_type, &1)
            )

          {:error, _reason} ->
            []
        end
    end
  end

  defp operational_metric_history_widget?(form) do
    form_value(form, :type) == "time_series" and operational_observable_widget?(form)
  end

  defp metric_history_picker_groups(observables) do
    grouped_observable_ids =
      metric_history_contracts()
      |> Enum.flat_map(& &1.observables)
      |> MapSet.new()

    contract_groups =
      metric_history_contracts()
      |> Enum.map(fn contract ->
        group_observables =
          Enum.filter(observables, &(observable_id(&1) in contract.observables))

        %{
          id: atom_value(contract.product),
          label: metric_history_group_label(contract),
          product: contract.product,
          product_family: contract.product_family,
          source_product_value: atom_value(contract.product),
          product_family_value: atom_value(contract.product_family),
          observables: group_observables
        }
      end)
      |> Enum.reject(&(&1.observables == []))

    fallback_observables =
      Enum.reject(observables, &(observable_id(&1) in grouped_observable_ids))

    if fallback_observables == [] do
      contract_groups
    else
      contract_groups ++
        [
          %{
            id: "operational_observables",
            label: "Other operational observables",
            source_product_value: "",
            product_family_value: "",
            observables: fallback_observables
          }
        ]
    end
  end

  defp metric_history_contract_for_observable(observable_id) when is_binary(observable_id) do
    Enum.find(metric_history_contracts(), &(observable_id in &1.observables))
  end

  defp metric_history_contract_for_observable(_observable_id), do: nil

  defp metric_history_contracts do
    {:ok, adapter_definition} =
      ExtensionCatalog.fetch_source_adapter(:operational_observables)

    adapter_definition.module.capabilities().metadata
    |> get_attr(:metric_history_contracts)
    |> List.wrap()
    |> Enum.map(&normalize_metric_history_contract/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_metric_history_contract(contract) when is_map(contract) do
    observables =
      contract
      |> get_attr(:observables)
      |> List.wrap()
      |> Enum.filter(&is_binary/1)

    product = contract |> get_attr(:product) |> normalize_contract_atom()
    product_family = contract |> get_attr(:product_family) |> normalize_contract_atom()

    if observables == [] or is_nil(product) or is_nil(product_family) do
      nil
    else
      %{observables: observables, product: product, product_family: product_family}
    end
  end

  defp normalize_metric_history_contract(_contract), do: nil

  defp normalize_contract_atom(value) when is_atom(value), do: value

  defp normalize_contract_atom(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> String.replace("-", "_")
    |> String.to_existing_atom()
  rescue
    ArgumentError -> nil
  end

  defp normalize_contract_atom(_value), do: nil

  defp metric_history_group_label(%{product_family: product_family}) do
    "#{product_family_label(product_family)} metric history"
  end

  defp product_family_label(product_family) do
    product_family
    |> atom_value()
    |> String.replace("_", " ")
    |> String.replace("rf", "RF")
  end

  defp atom_value(value) when is_atom(value), do: Atom.to_string(value)
  defp atom_value(value) when is_binary(value), do: value
  defp atom_value(_value), do: ""

  defp operational_observable_scopes(%OperationalObservable{} = observable),
    do: WidgetFrameContract.operational_observable_scopes(observable)

  defp operational_observable_scopes(observable) when is_map(observable) do
    scopes =
      [get_attr(observable, :primary_scope) | List.wrap(get_attr(observable, :optional_scopes))]
      |> Enum.map(&normalize_scope_kind/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    case scopes do
      [] ->
        observable
        |> get_attr(:observable_id)
        |> operational_observable_scopes()

      scopes ->
        scopes
    end
  end

  defp operational_observable_scopes(observable_id) when is_binary(observable_id),
    do: WidgetFrameContract.operational_observable_scopes(observable_id)

  defp operational_observable_scopes(_observable), do: []

  defp observable_id(%OperationalObservable{} = observable), do: observable.observable_id

  defp observable_id(observable) when is_map(observable), do: get_attr(observable, :observable_id)

  defp observable_id(observable_id) when is_binary(observable_id), do: observable_id

  defp observable_id(_observable), do: nil

  defp normalize_scope_kind(scope_kind) when is_atom(scope_kind) do
    if scope_kind in @scope_kinds, do: scope_kind
  end

  defp normalize_scope_kind(scope_kind) when is_binary(scope_kind) do
    normalized =
      scope_kind
      |> String.trim()
      |> String.downcase()
      |> String.replace("-", "_")

    Enum.find(@scope_kinds, &(Atom.to_string(&1) == normalized))
  end

  defp normalize_scope_kind(_scope_kind), do: nil

  defp scope_label(scope_kind) do
    scope_kind
    |> Atom.to_string()
    |> String.replace("_", " ")
  end

  defp scope_override_selector(%ScopeContext{} = scope_context) do
    primary_kind =
      scope_context
      |> ScopeContext.primary_kind()
      |> normalize_scope_kind()

    primary_id =
      scope_context
      |> ScopeContext.primary_ids()
      |> List.first()

    if primary_kind && present_id?(primary_id) do
      {primary_kind, primary_id}
    else
      typed_scope_selector(scope_context)
    end
  end

  defp typed_scope_selector(%ScopeContext{} = scope_context) do
    @scope_kinds
    |> Enum.find_value({nil, nil}, fn kind ->
      case ScopeContext.scope_id(scope_context, kind) do
        id when is_binary(id) and id != "" -> {kind, id}
        _missing -> nil
      end
    end)
  end

  defp present_id?(id), do: is_binary(id) and id != ""

  defp get_attr(attrs, key) when is_map(attrs),
    do: Map.get(attrs, key, Map.get(attrs, to_string(key)))
end
