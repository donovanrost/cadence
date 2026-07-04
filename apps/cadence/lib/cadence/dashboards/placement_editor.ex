defmodule Cadence.Dashboards.PlacementEditor do
  @moduledoc """
  Builds canonical dashboard placements from the current ops widget editor form.

  The web form still uses widget-oriented field names for a stable DOM contract,
  but this module is the dashboard-context write boundary: callers receive a
  `Cadence.Dashboards.Placement`.
  """

  alias Cadence.Dashboards.{
    OperationalObservable,
    Placement,
    WidgetDef,
    WidgetFrameContract,
    WidgetRegistry
  }

  alias Cadence.Dashboards.ScopeContext
  alias Cadence.Ids

  @type panel :: :add_widget | {:edit_placement, binary()} | term()
  @type result :: {:ok, Placement.t()} | {:error, {atom(), binary()}}
  @type selected_observables :: binary() | [binary()] | nil

  @precision_range 0..6
  @window_seconds_range 60..3600
  @value_tile_observable_range 1..1
  @time_series_observable_range 1..8
  @status_matrix_observable_range 1..24
  @data_table_observable_range 1..24

  @doc "Default params for an empty add-widget form."
  @spec form_defaults() :: map()
  def form_defaults do
    %{
      "type" => "value_tile",
      "title" => "",
      "mode" => "context",
      "spacecraft_id" => "",
      "scope_kind" => "",
      "scope_id" => "",
      "binding_source" => "telemetry",
      "precision" => "2",
      "window_seconds" => "300",
      "point_q" => ""
    }
  end

  @doc "Form params prefilled from an existing placement."
  @spec to_form_params(Placement.t()) :: map()
  def to_form_params(%Placement{} = placement) do
    widget_def = placement.widget_def || %WidgetDef{}
    type = type_from_widget_type_id(widget_def.widget_type_id)

    %{
      "type" => type || "",
      "title" => widget_def.title || "",
      "mode" => form_mode(placement, widget_def),
      "spacecraft_id" => scope_spacecraft_id(placement) || "",
      "scope_kind" => scope_override_kind(placement) || "",
      "scope_id" => scope_override_id(placement) || "",
      "binding_source" => widget_binding_source(widget_def),
      "precision" => option_string(widget_def.options, :precision, 2),
      "window_seconds" => option_string(widget_def.options, :window_seconds, 300),
      "point_q" => ""
    }
  end

  @doc """
  Builds a canonical placement from form params.

  Edits preserve the existing placement id and layout. Adds create an
  auto-positioned placement with the current widget minimums used by the ops UI.
  """
  @spec build_placement(map(), selected_observables(), panel(), Placement.t() | nil) :: result()
  def build_placement(params, selected_observables, panel, existing_placement \\ nil)
      when is_map(params) do
    build_placement(params, selected_observables, panel, existing_placement, [])
  end

  @spec build_placement(map(), selected_observables(), panel(), Placement.t() | nil, keyword()) ::
          result()
  def build_placement(params, selected_observables, panel, existing_placement, opts)
      when is_map(params) and is_list(opts) do
    with {:ok, type} <- normalize_type(params["type"]),
         title <- params["title"],
         :ok <- validate_title(title),
         {:ok, binding} <- binding(type, params, selected_observables),
         :ok <- validate_authoring_scope(binding, opts),
         {:ok, options} <- options(type, params) do
      placement =
        %Placement{
          placement_id: placement_id(panel, existing_placement),
          layout: placement_layout(type, existing_placement),
          widget_def: %WidgetDef{
            widget_type_id: widget_type_id(type),
            widget_type_version: 1,
            title: title,
            binding: binding,
            options: options
          },
          scope_override: scope_override(type, params)
        }

      {:ok, placement}
    end
  end

  @spec selected_observable(Placement.t() | nil) :: binary() | nil
  def selected_observable(%Placement{widget_def: %WidgetDef{binding: binding}}) do
    binding
    |> Map.get(:observables, [])
    |> List.first()
  end

  def selected_observable(_placement), do: nil

  @spec selected_observables(Placement.t() | nil) :: [binary()]
  def selected_observables(%Placement{widget_def: %WidgetDef{binding: binding}}) do
    binding
    |> Map.get(:observables, [])
    |> normalize_observables()
  end

  def selected_observables(_placement), do: []

  defp normalize_type("value_tile"), do: {:ok, :value_tile}
  defp normalize_type("time_series"), do: {:ok, :time_series}
  defp normalize_type("status_matrix"), do: {:ok, :status_matrix}
  defp normalize_type("data_table"), do: {:ok, :data_table}
  defp normalize_type("state_timeline"), do: {:ok, :state_timeline}
  defp normalize_type("event_timeline"), do: {:ok, :event_timeline}
  defp normalize_type("constellation_health"), do: {:ok, :constellation_health}
  defp normalize_type(type), do: {:error, {:invalid_type, "unsupported type: #{inspect(type)}"}}

  defp validate_title(title) when is_binary(title) do
    if String.length(title) in 1..120 do
      :ok
    else
      {:error, {:invalid_title, "must be 1 to 120 characters"}}
    end
  end

  defp validate_title(_title), do: {:error, {:invalid_title, "is required"}}

  defp binding(:constellation_health, _params, _selected_observables) do
    {:ok,
     %{
       observables: [],
       scope_mode: :context,
       data_mode: :context,
       value_type: :engineering,
       sampling: :constellation_health,
       overlays: []
     }}
  end

  defp binding(:event_timeline, _params, _selected_observables) do
    {:ok,
     %{
       source: :events,
       observables: [],
       scope_mode: :context,
       data_mode: :context,
       value_type: nil,
       sampling: :event_history,
       overlays: []
     }}
  end

  defp binding(:status_matrix, params, selected_observables) do
    multi_observable_binding(:status_matrix, params, selected_observables)
  end

  defp binding(:data_table, params, selected_observables) do
    multi_observable_binding(:data_table, params, selected_observables)
  end

  defp binding(:state_timeline, params, selected_observables) do
    source = state_timeline_binding_source_param(params)
    mode = params["mode"] || "context"
    spacecraft_id = if mode == "fixed", do: blank_to_nil(params["spacecraft_id"])
    observables = normalize_observables(selected_observables)

    case source do
      :operational_observables ->
        operational_state_timeline_binding(mode, observables, params)

      :limits ->
        telemetry_point_binding(
          :state_timeline,
          mode,
          spacecraft_id,
          List.first(observables),
          params
        )
    end
  end

  defp binding(:value_tile, params, selected_observables) do
    source = binding_source_param(params)
    mode = params["mode"] || "context"
    spacecraft_id = if mode == "fixed", do: blank_to_nil(params["spacecraft_id"])
    selected_point_id = selected_observables |> normalize_observables() |> List.first()

    with :ok <- validate_binding_source(:value_tile, source) do
      case source do
        :operational_observables ->
          selected_observables
          |> normalize_observables()
          |> operational_value_tile_binding(mode, params)

        :telemetry ->
          telemetry_point_binding(:value_tile, mode, spacecraft_id, selected_point_id, params)
      end
    end
  end

  defp binding(:time_series, params, selected_observables) do
    source = binding_source_param(params)
    mode = params["mode"] || "context"
    spacecraft_id = if mode == "fixed", do: blank_to_nil(params["spacecraft_id"])
    selected_point_id = selected_observables |> normalize_observables() |> List.first()

    with :ok <- validate_binding_source(:time_series, source) do
      case source do
        :operational_observables ->
          selected_observables
          |> normalize_observables()
          |> operational_time_series_binding(mode, params)

        :telemetry ->
          telemetry_point_binding(:time_series, mode, spacecraft_id, selected_point_id, params)
      end
    end
  end

  defp multi_observable_binding(type, params, selected_observables)
       when type in [:status_matrix, :data_table] do
    source = binding_source_param(params)
    mode = params["mode"] || "context"
    spacecraft_id = if mode == "fixed", do: blank_to_nil(params["spacecraft_id"])
    observables = normalize_observables(selected_observables)

    with :ok <- validate_binding_source(type, source) do
      case source do
        :operational_observables ->
          operational_multi_observable_binding(type, mode, observables, params)

        :telemetry ->
          telemetry_multi_observable_binding(type, mode, spacecraft_id, observables, params)
      end
    end
  end

  defp validate_binding_source(type, source) do
    type
    |> widget_type_id()
    |> WidgetRegistry.fetch_type(:latest)
    |> case do
      {:ok, widget_type} ->
        if WidgetFrameContract.supports_primary_source?(widget_type, source) do
          :ok
        else
          {:error, {:invalid_binding, "widget type does not support selected binding source"}}
        end

      {:error, _reason} ->
        {:error, {:invalid_type, "unsupported type: #{inspect(type)}"}}
    end
  end

  defp telemetry_point_binding(type, mode, spacecraft_id, selected_point_id, params)
       when type in [:value_tile, :time_series, :state_timeline] do
    cond do
      mode not in ["context", "fixed", "scope"] ->
        {:error, {:invalid_binding, "point widgets bind in context, fixed, or pinned-scope mode"}}

      blank?(selected_point_id) ->
        {:error, {:invalid_binding, "a telemetry point is required"}}

      mode == "fixed" and is_nil(spacecraft_id) ->
        {:error, {:invalid_binding, "fixed binding requires a spacecraft"}}

      mode == "scope" and invalid_scope_override?(params_scope_override(mode, params)) ->
        {:error, {:invalid_binding, "pinned scope requires an active dashboard context"}}

      true ->
        {:ok,
         %{
           source: point_binding_source(type),
           observables: [selected_point_id],
           scope_mode: binding_scope_mode(mode),
           data_mode: :context,
           value_type: :engineering,
           sampling: sampling(type),
           overlays: overlays(type)
         }}
    end
  end

  defp telemetry_multi_observable_binding(type, mode, spacecraft_id, observables, params)
       when type in [:status_matrix, :data_table] do
    cond do
      mode not in ["context", "fixed", "scope"] ->
        {:error,
         {:invalid_binding, "#{widget_label(type)} binds in context, fixed, or pinned-scope mode"}}

      length(observables) not in observable_range(type) ->
        {:error, {:invalid_binding, "select 1 to 24 telemetry points"}}

      mode == "fixed" and is_nil(spacecraft_id) ->
        {:error, {:invalid_binding, "fixed binding requires a spacecraft"}}

      mode == "scope" and invalid_scope_override?(params_scope_override(mode, params)) ->
        {:error, {:invalid_binding, "pinned scope requires an active dashboard context"}}

      true ->
        {:ok,
         %{
           source: :telemetry,
           observables: observables,
           scope_mode: binding_scope_mode(mode),
           data_mode: :context,
           value_type: :engineering,
           sampling: :latest,
           overlays: [:limits, :quality]
         }}
    end
  end

  defp operational_multi_observable_binding(_type, "fixed", _observables, _params) do
    {:error, {:invalid_binding, "operational observables use dashboard context or pinned scope"}}
  end

  defp operational_multi_observable_binding(type, mode, observables, params)
       when type in [:status_matrix, :data_table] and mode in ["context", "scope", nil] do
    cond do
      length(observables) not in observable_range(type) ->
        {:error, {:invalid_binding, "select 1 to 24 operational observables"}}

      unbacked_operational_observables?(observables) ->
        {:error, {:invalid_binding, "select backed operational observables"}}

      unsupported_operational_observables?(type, observables) ->
        {:error, {:invalid_binding, "select operational observables supported by this widget"}}

      mode == "scope" and invalid_scope_override?(params_scope_override(mode, params)) ->
        {:error, {:invalid_binding, "pinned scope requires an active dashboard context"}}

      true ->
        {:ok,
         %{
           source: :operational_observables,
           observables: observables,
           scope_mode: binding_scope_mode(mode),
           data_mode: :context,
           value_type: :engineering,
           sampling: :latest,
           overlays: []
         }}
    end
  end

  defp operational_multi_observable_binding(_type, _mode, _observables, _params) do
    {:error, {:invalid_binding, "operational observables use dashboard context or pinned scope"}}
  end

  defp operational_state_timeline_binding("fixed", _observables, _params) do
    {:error, {:invalid_binding, "operational observables use dashboard context or pinned scope"}}
  end

  defp operational_state_timeline_binding(mode, observables, params)
       when mode in ["context", "scope", nil] do
    cond do
      length(observables) not in @status_matrix_observable_range ->
        {:error, {:invalid_binding, "select 1 to 24 operational state observables"}}

      unbacked_operational_observables?(observables) ->
        {:error, {:invalid_binding, "select backed operational state observables"}}

      unsupported_operational_observables?(:state_timeline, observables) ->
        {:error, {:invalid_binding, "select operational observables supported by this widget"}}

      mode == "scope" and invalid_scope_override?(params_scope_override(mode, params)) ->
        {:error, {:invalid_binding, "pinned scope requires an active dashboard context"}}

      true ->
        {:ok,
         %{
           source: :operational_observables,
           observables: observables,
           scope_mode: binding_scope_mode(mode),
           data_mode: :context,
           value_type: :engineering,
           sampling: :event_history,
           overlays: []
         }}
    end
  end

  defp operational_state_timeline_binding(_mode, _observables, _params) do
    {:error, {:invalid_binding, "operational observables use dashboard context or pinned scope"}}
  end

  defp operational_value_tile_binding(_observables, "fixed", _params) do
    {:error, {:invalid_binding, "operational observables use dashboard context or pinned scope"}}
  end

  defp operational_value_tile_binding(observables, mode, params)
       when mode in ["context", "scope", nil] do
    cond do
      length(observables) not in @value_tile_observable_range ->
        {:error, {:invalid_binding, "select one operational metric observable"}}

      unbacked_operational_observables?(observables) ->
        {:error, {:invalid_binding, "select one backed operational metric observable"}}

      unsupported_operational_observables?(:value_tile, observables) ->
        {:error, {:invalid_binding, "select an operational observable supported by this widget"}}

      mode == "scope" and invalid_scope_override?(params_scope_override(mode, params)) ->
        {:error, {:invalid_binding, "pinned scope requires an active dashboard context"}}

      true ->
        {:ok,
         %{
           source: :operational_observables,
           observables: observables,
           scope_mode: binding_scope_mode(mode),
           data_mode: :context,
           value_type: :engineering,
           sampling: :latest,
           overlays: []
         }}
    end
  end

  defp operational_value_tile_binding(_observables, _mode, _params) do
    {:error, {:invalid_binding, "operational observables use dashboard context or pinned scope"}}
  end

  defp operational_time_series_binding(_observables, "fixed", _params) do
    {:error, {:invalid_binding, "operational observables use dashboard context or pinned scope"}}
  end

  defp operational_time_series_binding(observables, mode, params)
       when mode in ["context", "scope", nil] do
    cond do
      length(observables) not in @time_series_observable_range ->
        {:error, {:invalid_binding, "select 1 to 8 operational metric observables"}}

      unbacked_operational_observables?(observables) ->
        {:error, {:invalid_binding, "select backed operational metric observables"}}

      unsupported_operational_observables?(:time_series, observables) ->
        {:error,
         {:invalid_binding, "select operational metric observables supported by this widget"}}

      mode == "scope" and invalid_scope_override?(params_scope_override(mode, params)) ->
        {:error, {:invalid_binding, "pinned scope requires an active dashboard context"}}

      true ->
        {:ok,
         %{
           source: :operational_observables,
           observables: observables,
           scope_mode: binding_scope_mode(mode),
           data_mode: :context,
           value_type: :engineering,
           sampling: :raw_series,
           overlays: [:events, :quality]
         }}
    end
  end

  defp operational_time_series_binding(_observables, _mode, _params) do
    {:error, {:invalid_binding, "operational observables use dashboard context or pinned scope"}}
  end

  defp unbacked_operational_observables?(observable_ids),
    do: Enum.any?(observable_ids, &(not OperationalObservable.backed?(&1)))

  defp unsupported_operational_observables?(type, observable_ids) do
    case type |> widget_type_id() |> WidgetRegistry.fetch_type(:latest) do
      {:ok, widget_type} ->
        Enum.any?(observable_ids, &unsupported_operational_observable?(widget_type, &1))

      {:error, _reason} ->
        true
    end
  end

  defp unsupported_operational_observable?(widget_type, observable_id) do
    case OperationalObservable.fetch(observable_id) do
      {:ok, observable} ->
        not WidgetFrameContract.operational_observable_supported?(widget_type, observable)

      {:error, _reason} ->
        true
    end
  end

  defp validate_authoring_scope(
         %{source: :operational_observables, observables: observables},
         opts
       ) do
    scope_kind =
      opts
      |> Keyword.get(:authoring_scope_context)
      |> ScopeContext.primary_kind()

    case WidgetFrameContract.unsupported_operational_observable_scope_ids(observables, scope_kind) do
      [] ->
        :ok

      unsupported ->
        {:error,
         {:invalid_binding,
          "selected context does not support operational observables: #{Enum.join(unsupported, ", ")}"}}
    end
  end

  defp validate_authoring_scope(_binding, _opts), do: :ok

  defp options(:event_timeline, _params), do: {:ok, %{}}
  defp options(:constellation_health, _params), do: {:ok, %{}}

  defp options(type, params)
       when type in [:value_tile, :time_series, :status_matrix, :data_table, :state_timeline] do
    precision = parse_int(params["precision"], 2)
    window_seconds = parse_int(params["window_seconds"], 300)

    cond do
      precision not in @precision_range ->
        {:error, {:invalid_options, "precision must be between 0 and 6"}}

      window_seconds not in @window_seconds_range ->
        {:error, {:invalid_options, "window must be between 60 and 3600 seconds"}}

      type == :time_series ->
        {:ok, %{precision: precision, window_seconds: window_seconds}}

      type in [:status_matrix, :data_table, :state_timeline] ->
        {:ok, %{precision: precision, window_seconds: window_seconds}}

      true ->
        {:ok, %{precision: precision, window_seconds: window_seconds, show_unit: true}}
    end
  end

  defp placement_id({:edit_placement, placement_id}, %Placement{}), do: placement_id
  defp placement_id(_panel, %Placement{placement_id: placement_id}), do: placement_id
  defp placement_id(_panel, _existing_placement), do: Ids.new("dash_widget")

  defp placement_layout(_type, %Placement{layout: layout}) when is_map(layout), do: layout
  defp placement_layout(:value_tile, _existing_placement), do: %{x: nil, y: nil, w: 4, h: 2}
  defp placement_layout(:time_series, _existing_placement), do: %{x: nil, y: nil, w: 4, h: 3}
  defp placement_layout(:status_matrix, _existing_placement), do: %{x: nil, y: nil, w: 4, h: 3}
  defp placement_layout(:data_table, _existing_placement), do: %{x: nil, y: nil, w: 6, h: 4}
  defp placement_layout(:state_timeline, _existing_placement), do: %{x: nil, y: nil, w: 6, h: 3}
  defp placement_layout(:event_timeline, _existing_placement), do: %{x: nil, y: nil, w: 6, h: 4}

  defp placement_layout(:constellation_health, _existing_placement),
    do: %{x: nil, y: nil, w: 4, h: 3}

  defp scope_override(:event_timeline, _params), do: nil
  defp scope_override(:constellation_health, _params), do: nil

  defp scope_override(_type, params) do
    params
    |> Map.get("mode")
    |> params_scope_override(params)
  end

  defp params_scope_override("fixed", params) do
    spacecraft_id = blank_to_nil(params["spacecraft_id"])

    case spacecraft_id do
      nil ->
        nil

      spacecraft_id ->
        %{primary: %{kind: "spacecraft", mode: "one", ids: [spacecraft_id]}}
    end
  end

  defp params_scope_override("scope", params) do
    scope_kind = normalize_scope_kind(params && params["scope_kind"])
    scope_id = blank_to_nil(params && params["scope_id"])

    cond do
      is_nil(scope_kind) -> nil
      is_nil(scope_id) -> nil
      true -> %{primary: %{kind: Atom.to_string(scope_kind), mode: "one", ids: [scope_id]}}
    end
  end

  defp params_scope_override(_mode, _params), do: nil

  defp invalid_scope_override?(nil), do: true
  defp invalid_scope_override?(_scope_override), do: false

  defp binding_scope_mode("fixed"), do: :override
  defp binding_scope_mode("scope"), do: :override
  defp binding_scope_mode(_mode), do: :context

  defp sampling(:value_tile), do: :latest
  defp sampling(:time_series), do: :raw_series
  defp sampling(:state_timeline), do: :event_history

  defp overlays(:value_tile), do: [:limits, :quality]
  defp overlays(:time_series), do: [:limits, :events, :quality]
  defp overlays(:state_timeline), do: [:quality]

  defp point_binding_source(:state_timeline), do: :limits
  defp point_binding_source(_type), do: :telemetry

  defp widget_type_id(:value_tile), do: "cadence.value_tile"
  defp widget_type_id(:time_series), do: "cadence.time_series"
  defp widget_type_id(:status_matrix), do: "cadence.status_matrix"
  defp widget_type_id(:data_table), do: "cadence.data_table"
  defp widget_type_id(:state_timeline), do: "cadence.state_timeline"
  defp widget_type_id(:event_timeline), do: "cadence.event_timeline"
  defp widget_type_id(:constellation_health), do: "cadence.constellation_health"

  defp type_from_widget_type_id("cadence.value_tile"), do: "value_tile"
  defp type_from_widget_type_id("cadence.time_series"), do: "time_series"
  defp type_from_widget_type_id("cadence.status_matrix"), do: "status_matrix"
  defp type_from_widget_type_id("cadence.data_table"), do: "data_table"
  defp type_from_widget_type_id("cadence.state_timeline"), do: "state_timeline"
  defp type_from_widget_type_id("cadence.event_timeline"), do: "event_timeline"
  defp type_from_widget_type_id("cadence.constellation_health"), do: "constellation_health"
  defp type_from_widget_type_id(_widget_type_id), do: nil

  defp observable_range(:data_table), do: @data_table_observable_range
  defp observable_range(:status_matrix), do: @status_matrix_observable_range

  defp widget_label(:data_table), do: "data table"
  defp widget_label(:status_matrix), do: "status matrix"

  defp form_mode(%Placement{} = placement, %WidgetDef{} = widget_def) do
    cond do
      widget_def.widget_type_id == "cadence.event_timeline" -> "context"
      widget_def.widget_type_id == "cadence.constellation_health" -> "constellation"
      scope_override_kind(placement) in [nil, ""] -> "context"
      scope_override_kind(placement) == "spacecraft" -> "fixed"
      true -> "scope"
    end
  end

  defp widget_binding_source(%WidgetDef{binding: binding}) when is_map(binding) do
    case Map.get(binding, :source, Map.get(binding, "source", :telemetry)) do
      :operational_observables -> "operational_observables"
      "operational_observables" -> "operational_observables"
      :events -> "events"
      "events" -> "events"
      _other -> "telemetry"
    end
  end

  defp widget_binding_source(_widget_def), do: "telemetry"

  defp binding_source_param(%{"binding_source" => "operational_observables"}),
    do: :operational_observables

  defp binding_source_param(%{"binding_source" => :operational_observables}),
    do: :operational_observables

  defp binding_source_param(%{"binding_source" => "limits"}), do: :limits
  defp binding_source_param(%{"binding_source" => :limits}), do: :limits

  defp binding_source_param(_params), do: :telemetry

  defp state_timeline_binding_source_param(params) do
    case binding_source_param(params) do
      :operational_observables -> :operational_observables
      _other -> :limits
    end
  end

  defp scope_override_primary(%Placement{scope_override: scope_override})
       when is_map(scope_override) do
    primary = Map.get(scope_override, :primary, Map.get(scope_override, "primary", %{}))
    if is_map(primary), do: primary, else: %{}
  end

  defp scope_override_primary(_placement), do: %{}

  defp scope_spacecraft_id(%Placement{} = placement) do
    if scope_override_kind(placement) == "spacecraft" do
      scope_override_id(placement)
    end
  end

  defp scope_override_kind(%Placement{} = placement) do
    placement
    |> scope_override_primary()
    |> get_attr(:kind)
    |> normalize_scope_kind()
    |> case do
      nil -> nil
      kind -> Atom.to_string(kind)
    end
  end

  defp scope_override_id(%Placement{} = placement) do
    placement
    |> scope_override_primary()
    |> get_attr(:ids)
    |> List.wrap()
    |> Enum.find(&(is_binary(&1) and &1 != ""))
  end

  defp option_string(options, key, default) when is_map(options) do
    options
    |> Map.get(key, Map.get(options, to_string(key), default))
    |> to_string()
  end

  defp parse_int(value, default) do
    case Integer.parse(to_string(value)) do
      {int, _rest} -> int
      :error -> default
    end
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(value), do: value

  @scope_kinds [
    :mission,
    :spacecraft,
    :contact,
    :ground_station,
    :source_endpoint,
    :transport,
    :link
  ]

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

  defp normalize_observables(value) do
    value
    |> List.wrap()
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.uniq()
  end

  defp get_attr(attrs, key) when is_map(attrs),
    do: Map.get(attrs, key, Map.get(attrs, to_string(key)))
end
