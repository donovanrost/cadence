defmodule Cadence.Dashboards.RenderWidget do
  @moduledoc """
  Canonical widget presenter used by the current dashboard LiveView.

  This is intentionally shaped like the fields the existing components need,
  and is derived directly from a dashboard placement.
  """

  alias Cadence.Dashboards.{Placement, WidgetDef}

  @type widget_type ::
          :value_tile
          | :time_series
          | :status_matrix
          | :data_table
          | :state_timeline
          | :event_timeline
          | :constellation_health

  @type binding :: %{
          source: :telemetry | :limits | :operational_observables | :events,
          mode: :fixed | :context | :repeat | :constellation,
          spacecraft_id: binary() | nil,
          point_id: binary() | nil,
          point_ids: [binary()]
        }

  @type options :: %{
          precision: non_neg_integer(),
          window_seconds: pos_integer()
        }

  @type t :: %__MODULE__{
          widget_id: binary(),
          widget_type_id: binary(),
          widget_type_version: pos_integer(),
          type: widget_type(),
          title: binary(),
          binding: binding(),
          options: options()
        }

  defstruct [
    :widget_id,
    :widget_type_id,
    :type,
    :title,
    widget_type_version: 1,
    binding: %{source: :telemetry, mode: :context, spacecraft_id: nil, point_id: nil},
    options: %{precision: 2, window_seconds: 300}
  ]

  @spec from_placement(Placement.t()) :: {:ok, t()} | :error
  def from_placement(%Placement{widget_def: %WidgetDef{} = widget_def} = placement) do
    with {:ok, type} <- widget_type(widget_def.widget_type_id) do
      {:ok,
       %__MODULE__{
         widget_id: placement.placement_id,
         widget_type_id: widget_def.widget_type_id,
         widget_type_version: widget_def.widget_type_version,
         type: type,
         title: widget_def.title,
         binding: binding_from_placement(type, placement, widget_def),
         options: options_from_widget_def(type, widget_def)
       }}
    end
  end

  def from_placement(%Placement{}), do: :error

  defp widget_type("cadence.value_tile"), do: {:ok, :value_tile}
  defp widget_type("cadence.time_series"), do: {:ok, :time_series}
  defp widget_type("cadence.status_matrix"), do: {:ok, :status_matrix}
  defp widget_type("cadence.data_table"), do: {:ok, :data_table}
  defp widget_type("cadence.state_timeline"), do: {:ok, :state_timeline}
  defp widget_type("cadence.event_timeline"), do: {:ok, :event_timeline}
  defp widget_type("cadence.constellation_health"), do: {:ok, :constellation_health}
  defp widget_type(_widget_type_id), do: :error

  defp binding_from_placement(:event_timeline, _placement, _widget_def) do
    %{
      source: :events,
      mode: :context,
      spacecraft_id: nil,
      point_id: nil,
      point_ids: []
    }
  end

  defp binding_from_placement(:constellation_health, _placement, _widget_def) do
    %{
      source: :operational_observables,
      mode: :constellation,
      spacecraft_id: nil,
      point_id: nil,
      point_ids: []
    }
  end

  defp binding_from_placement(_type, placement, widget_def) do
    mode = binding_mode(placement, widget_def)
    point_ids = Map.get(widget_def.binding, :observables, [])

    %{
      source: binding_source(widget_def),
      mode: mode,
      spacecraft_id: if(mode == :fixed, do: fixed_spacecraft_id(placement), else: nil),
      point_id: List.first(point_ids),
      point_ids: point_ids
    }
  end

  defp binding_mode(placement, widget_def) do
    cond do
      fixed_spacecraft_id(placement) -> :fixed
      Map.get(widget_def.binding, :scope_mode) == :override -> :fixed
      Map.get(widget_def.binding, :scope_mode) == :repeat -> :repeat
      true -> :context
    end
  end

  defp binding_source(%WidgetDef{binding: binding}) when is_map(binding) do
    case Map.get(binding, :source, Map.get(binding, "source", :telemetry)) do
      :operational_observables -> :operational_observables
      "operational_observables" -> :operational_observables
      :limits -> :limits
      "limits" -> :limits
      :events -> :events
      "events" -> :events
      _source -> :telemetry
    end
  end

  defp binding_source(_widget_def), do: :telemetry

  defp fixed_spacecraft_id(%{scope_override: scope_override}) when is_map(scope_override) do
    primary = Map.get(scope_override, :primary, Map.get(scope_override, "primary", %{}))

    primary
    |> Map.get(:ids, Map.get(primary, "ids", []))
    |> List.wrap()
    |> List.first()
  end

  defp fixed_spacecraft_id(_placement), do: nil

  defp options_from_widget_def(:value_tile, widget_def) do
    %{
      precision: get_option(widget_def.options, :precision, 2),
      window_seconds: get_option(widget_def.options, :window_seconds, 300),
      show_unit: get_option(widget_def.options, :show_unit, true)
    }
  end

  defp options_from_widget_def(:time_series, widget_def) do
    %{
      precision: get_option(widget_def.options, :precision, 2),
      window_seconds: get_option(widget_def.options, :window_seconds, 300),
      show_min_max_band: get_option(widget_def.options, :show_min_max_band, true),
      legend_mode: legend_mode(widget_def.options),
      line_width: get_option(widget_def.options, :line_width, "normal"),
      fill_opacity: get_option(widget_def.options, :fill_opacity, 0),
      span_gaps: get_option(widget_def.options, :span_gaps, false),
      show_points: get_option(widget_def.options, :show_points, false),
      axis_mode: get_option(widget_def.options, :axis_mode, "unit"),
      shared_tooltip: get_option(widget_def.options, :shared_tooltip, true)
    }
  end

  defp options_from_widget_def(type, widget_def)
       when type in [:status_matrix, :data_table, :state_timeline] do
    %{
      precision: get_option(widget_def.options, :precision, 2),
      window_seconds: get_option(widget_def.options, :window_seconds, 300)
    }
  end

  defp options_from_widget_def(:event_timeline, _widget_def) do
    %{precision: 2, window_seconds: 300}
  end

  defp options_from_widget_def(:constellation_health, _widget_def) do
    %{precision: 2, window_seconds: 300}
  end

  defp get_option(options, key, default) when is_map(options) do
    Map.get(options, key, Map.get(options, to_string(key), default))
  end

  defp legend_mode(options) when is_map(options) do
    case get_option(options, :legend_mode, nil) do
      nil -> if(get_option(options, :legend, false), do: "always", else: "auto")
      mode -> mode
    end
  end
end
