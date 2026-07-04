defmodule Cadence.Dashboards.WidgetDef do
  @moduledoc """
  Dashboard widget definition.

  The widget definition is the "what" of a placement: type, title, binding, and
  options. Layout remains on `Cadence.Dashboards.Placement`.
  """

  @type t :: %__MODULE__{
          widget_type_id: binary(),
          widget_type_version: pos_integer(),
          title: binary() | nil,
          binding: map(),
          options: map()
        }

  defstruct [
    :widget_type_id,
    :title,
    widget_type_version: 1,
    binding: %{},
    options: %{}
  ]

  @spec from_map(map()) :: t()
  def from_map(attrs) when is_map(attrs) do
    %__MODULE__{
      widget_type_id: get_attr(attrs, :widget_type_id),
      widget_type_version: get_attr(attrs, :widget_type_version) || 1,
      title: get_attr(attrs, :title),
      binding: normalize_binding(get_attr(attrs, :binding) || %{}),
      options: get_attr(attrs, :options) || %{}
    }
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = widget_def) do
    %{
      widget_type_id: widget_def.widget_type_id,
      widget_type_version: widget_def.widget_type_version,
      title: widget_def.title,
      binding: widget_def.binding,
      options: widget_def.options
    }
  end

  defp normalize_binding(binding) do
    source =
      normalize_atom(get_attr(binding, :source), :telemetry, %{
        :telemetry => :telemetry,
        "telemetry" => :telemetry,
        :operational_observables => :operational_observables,
        "operational_observables" => :operational_observables,
        :limits => :limits,
        "limits" => :limits,
        :events => :events,
        "events" => :events
      })

    %{
      source: source,
      observables: binding |> get_attr(:observables) |> List.wrap(),
      scope_mode:
        normalize_atom(get_attr(binding, :scope_mode), :context, %{
          :context => :context,
          "context" => :context,
          :override => :override,
          "override" => :override,
          :repeat => :repeat,
          "repeat" => :repeat
        }),
      data_mode:
        normalize_atom(get_attr(binding, :data_mode), :context, %{
          :context => :context,
          "context" => :context,
          :override => :override,
          "override" => :override
        }),
      value_type:
        normalize_atom(get_attr(binding, :value_type), default_value_type(source), %{
          :engineering => :engineering,
          "engineering" => :engineering,
          :raw => :raw,
          "raw" => :raw
        }),
      sampling:
        normalize_atom(get_attr(binding, :sampling), :latest, %{
          :latest => :latest,
          "latest" => :latest,
          :raw_series => :raw_series,
          "raw_series" => :raw_series,
          :decimated_envelope => :decimated_envelope,
          "decimated_envelope" => :decimated_envelope,
          :constellation_health => :constellation_health,
          "constellation_health" => :constellation_health,
          :event_history => :event_history,
          "event_history" => :event_history
        }),
      aggregation: get_attr(binding, :aggregation),
      overlays:
        binding
        |> get_attr(:overlays)
        |> List.wrap()
        |> Enum.map(&normalize_overlay/1)
        |> Enum.reject(&is_nil/1)
    }
  end

  defp normalize_overlay(value) when value in [:limits, "limits"], do: :limits
  defp normalize_overlay(value) when value in [:events, "events"], do: :events
  defp normalize_overlay(value) when value in [:quality, "quality"], do: :quality
  defp normalize_overlay(_value), do: nil

  defp default_value_type(:events), do: nil
  defp default_value_type(_source), do: :engineering

  defp normalize_atom(nil, default, _mapping), do: default
  defp normalize_atom(value, _default, mapping), do: Map.get(mapping, value, value)

  defp get_attr(attrs, key) when is_map(attrs),
    do: Map.get(attrs, key, Map.get(attrs, to_string(key)))
end
