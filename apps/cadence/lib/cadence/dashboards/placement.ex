defmodule Cadence.Dashboards.Placement do
  @moduledoc """
  A widget placement in a dashboard document.

  Placement owns layout. Widget definitions remain layout-free so they can
  later be embedded directly or referenced through library widgets.
  """

  alias Cadence.Dashboards.WidgetDef

  @type t :: %__MODULE__{
          placement_id: binary(),
          section_id: binary() | nil,
          layout: map(),
          content_kind: :embedded | :library,
          widget_def: WidgetDef.t() | nil,
          library_widget_id: binary() | nil,
          library_version: pos_integer() | nil,
          overrides: map() | nil,
          repeat: map() | nil,
          scope_override: map() | nil,
          data_override: map() | nil,
          limit_override: map() | nil
        }

  defstruct [
    :placement_id,
    :section_id,
    :widget_def,
    :library_widget_id,
    :library_version,
    :overrides,
    :repeat,
    :scope_override,
    :data_override,
    :limit_override,
    content_kind: :embedded,
    layout: %{x: 0, y: 0, w: 4, h: 2}
  ]

  @spec from_map(map()) :: t()
  def from_map(attrs) when is_map(attrs) do
    content = get_attr(attrs, :content) || %{}
    repeat = get_attr(attrs, :repeat)

    %__MODULE__{
      placement_id: get_attr(attrs, :placement_id),
      section_id: get_attr(attrs, :section_id),
      layout: normalize_layout(get_attr(attrs, :layout) || %{}),
      content_kind: normalize_content_kind(get_attr(content, :kind)),
      widget_def: normalize_widget_def(content),
      library_widget_id: get_attr(content, :library_widget_id),
      library_version: get_attr(content, :library_version),
      overrides: get_attr(content, :overrides),
      repeat: normalize_repeat(repeat),
      scope_override: get_attr(attrs, :scope_override),
      data_override: get_attr(attrs, :data_override),
      limit_override: get_attr(attrs, :limit_override)
    }
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = placement) do
    %{
      placement_id: placement.placement_id,
      section_id: placement.section_id,
      layout: placement.layout,
      content: content_to_map(placement),
      repeat: placement.repeat,
      scope_override: placement.scope_override,
      data_override: placement.data_override,
      limit_override: placement.limit_override
    }
  end

  defp content_to_map(%__MODULE__{content_kind: :library} = placement) do
    %{
      kind: :library,
      library_widget_id: placement.library_widget_id,
      library_version: placement.library_version,
      overrides: placement.overrides
    }
  end

  defp content_to_map(%__MODULE__{} = placement) do
    %{
      kind: :embedded,
      widget_def: placement.widget_def && WidgetDef.to_map(placement.widget_def)
    }
  end

  defp normalize_layout(layout) do
    %{
      x: layout_value(layout, :x, 0),
      y: layout_value(layout, :y, 0),
      w: get_attr(layout, :w) || 4,
      h: get_attr(layout, :h) || 2,
      min_w: get_attr(layout, :min_w),
      min_h: get_attr(layout, :min_h)
    }
  end

  defp normalize_widget_def(content) do
    case get_attr(content, :widget_def) do
      nil -> nil
      widget_def -> WidgetDef.from_map(widget_def)
    end
  end

  defp normalize_repeat(nil), do: nil

  defp normalize_repeat(repeat) when is_map(repeat) do
    %{
      axis:
        normalize_atom(get_attr(repeat, :axis), %{:scope => :scope, "scope" => :scope}, :scope),
      over:
        normalize_atom(
          get_attr(repeat, :over),
          %{
            :spacecraft => :spacecraft,
            "spacecraft" => :spacecraft,
            :contact => :contact,
            "contact" => :contact,
            :ground_station => :ground_station,
            "ground_station" => :ground_station,
            :transport => :transport,
            "transport" => :transport,
            :link => :link,
            "link" => :link
          },
          nil
        ),
      layout:
        normalize_atom(
          get_attr(repeat, :layout),
          %{
            :row => :row,
            "row" => :row,
            :column => :column,
            "column" => :column,
            :wrap_grid => :wrap_grid,
            "wrap_grid" => :wrap_grid
          },
          :wrap_grid
        ),
      max_instances: get_attr(repeat, :max_instances) || 24
    }
  end

  defp normalize_content_kind(value) when value in [:embedded, "embedded", nil], do: :embedded
  defp normalize_content_kind(value) when value in [:library, "library"], do: :library
  defp normalize_content_kind(_value), do: :embedded

  defp normalize_atom(value, mapping, default), do: Map.get(mapping, value, default)

  defp get_attr(attrs, key) when is_map(attrs),
    do: Map.get(attrs, key, Map.get(attrs, to_string(key)))

  defp layout_value(layout, key, default) do
    cond do
      Map.has_key?(layout, key) -> Map.get(layout, key)
      Map.has_key?(layout, to_string(key)) -> Map.get(layout, to_string(key))
      true -> default
    end
  end
end
