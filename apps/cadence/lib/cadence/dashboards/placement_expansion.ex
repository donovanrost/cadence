defmodule Cadence.Dashboards.PlacementExpansion do
  @moduledoc """
  Expands authored dashboard placements into runtime placement instances.

  Dashboard documents keep repeat declarations as authoring metadata. The
  engine and presenter consume expanded placements so each repeated instance has
  stable placement identity, scope, layout, request ids, cache keys, and links.
  """

  alias Cadence.Dashboards.{Document, Placement, ScopeContext}

  @type scope_context :: map() | struct() | nil

  @spec expand(Document.t(), scope_context()) :: [Placement.t()]
  def expand(%Document{} = document, runtime_scope_context \\ nil) do
    Enum.flat_map(document.placements, &expand_placement(document, &1, runtime_scope_context))
  end

  @spec authored_placement_id(binary()) :: binary()
  def authored_placement_id(placement_id) when is_binary(placement_id) do
    placement_id
    |> String.split("__repeat_", parts: 2)
    |> List.first()
  end

  defp expand_placement(%Document{} = document, %Placement{repeat: repeat} = placement, runtime)
       when is_map(repeat) do
    if Map.get(repeat, :axis) == :scope and Map.get(repeat, :over) do
      scope_context = resolved_scope_context(document, placement, runtime)
      repeat_kind = Map.fetch!(repeat, :over)

      case repeat_ids(scope_context, repeat_kind, Map.get(repeat, :max_instances, 24)) do
        [] -> [placement]
        ids -> Enum.with_index(ids, &repeat_instance(document, placement, &1, &2))
      end
    else
      [placement]
    end
  end

  defp expand_placement(_document, %Placement{} = placement, _runtime), do: [placement]

  defp repeat_instance(%Document{} = document, %Placement{} = placement, scope_id, index) do
    repeat = placement.repeat || %{}
    repeat_kind = Map.fetch!(repeat, :over)

    %Placement{
      placement
      | placement_id: repeat_placement_id(placement.placement_id, repeat_kind, scope_id),
        layout: repeat_layout(document, placement.layout, repeat, index),
        scope_override: repeat_scope_override(placement.scope_override, repeat_kind, scope_id),
        repeat: nil
    }
  end

  defp resolved_scope_context(%Document{} = document, %Placement{} = placement, runtime) do
    ScopeContext.resolve(runtime, document_scope_defaults(document), placement.scope_override)
  end

  defp document_scope_defaults(%Document{defaults: defaults}) when is_map(defaults) do
    Map.get(defaults, "scope") || Map.get(defaults, :scope) || %{}
  end

  defp document_scope_defaults(%Document{}), do: %{}

  defp repeat_ids(%ScopeContext{} = scope_context, repeat_kind, max_instances) do
    cond do
      same_scope_kind?(ScopeContext.primary_kind(scope_context), repeat_kind) ->
        ScopeContext.primary_ids(scope_context)

      id = ScopeContext.scope_id(scope_context, repeat_kind) ->
        [id]

      true ->
        []
    end
    |> Enum.take(max_instances(max_instances))
  end

  defp max_instances(value) when is_integer(value) and value > 0, do: value
  defp max_instances(_value), do: 24

  defp repeat_placement_id(placement_id, repeat_kind, scope_id) do
    Enum.join([placement_id, "repeat", Atom.to_string(repeat_kind), safe_id(scope_id)], "__")
  end

  defp safe_id(value) when is_binary(value) do
    value
    |> String.replace(~r/[^A-Za-z0-9_-]+/, "-")
    |> String.trim("-")
  end

  defp safe_id(value), do: value |> to_string() |> safe_id()

  defp repeat_scope_override(scope_override, repeat_kind, scope_id) do
    scope_override
    |> scope_override_map()
    |> Map.put(:primary, %{kind: Atom.to_string(repeat_kind), mode: "one", ids: [scope_id]})
  end

  defp scope_override_map(scope_override) when is_map(scope_override), do: scope_override
  defp scope_override_map(_scope_override), do: %{}

  defp repeat_layout(%Document{} = document, layout, repeat, index) do
    case Map.get(repeat, :layout, :wrap_grid) do
      :row -> offset_layout(layout, index, :x)
      :column -> offset_layout(layout, index, :y)
      _wrap_grid -> wrap_grid_layout(document, layout, index)
    end
  end

  defp offset_layout(layout, index, axis) do
    step = positive_integer(Map.get(layout, :w), 1)
    step = if axis == :x, do: step, else: positive_integer(Map.get(layout, :h), 1)

    Map.update(layout, axis, index * step, fn
      value when is_integer(value) -> value + index * step
      value -> value
    end)
  end

  defp wrap_grid_layout(%Document{} = document, layout, index) do
    columns =
      document.grid
      |> Map.get(:columns, Map.get(document.grid, "columns", 12))
      |> positive_integer(12)

    base_x = integer_or_zero(Map.get(layout, :x))
    base_y = integer_or_zero(Map.get(layout, :y))
    width = positive_integer(Map.get(layout, :w), 1)
    height = positive_integer(Map.get(layout, :h), 1)
    available_columns = max(columns - base_x, width)
    per_row = max(div(available_columns, width), 1)

    %{
      layout
      | x: base_x + rem(index, per_row) * width,
        y: base_y + div(index, per_row) * height
    }
  end

  defp integer_or_zero(value) when is_integer(value), do: value
  defp integer_or_zero(_value), do: 0

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value, default), do: default

  defp same_scope_kind?(left, right) when is_atom(left) and is_atom(right), do: left == right

  defp same_scope_kind?(left, right) when not is_nil(left) and not is_nil(right) do
    to_string(left) == to_string(right)
  end

  defp same_scope_kind?(_left, _right), do: false
end
