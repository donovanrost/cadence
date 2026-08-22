defmodule Cadence.Dashboards.AnnotationComposition do
  @moduledoc """
  Resolves the annotation layers explicitly composed into a dashboard widget.

  Source adapters may contribute any registered annotation layer. A placement
  receives only the layers named by its widget definition, keeping adapter
  output independent from dashboard composition and preserving safe batching
  across placements with different layer selections.
  """

  alias Cadence.Dashboards.{Annotation, WidgetDef}

  @spec layer_ids(WidgetDef.t() | map() | nil) :: [binary()]
  def layer_ids(%WidgetDef{options: options}), do: layer_ids_from_options(options)

  def layer_ids(widget_def) when is_map(widget_def) do
    widget_def
    |> attr(:options, %{})
    |> layer_ids_from_options()
  end

  def layer_ids(_widget_def), do: []

  @spec select([Annotation.t()], [binary()]) :: [Annotation.t()]
  def select(annotations, layer_ids) when is_list(annotations) and is_list(layer_ids) do
    enabled_layer_ids = MapSet.new(normalize_layer_refs(layer_ids))

    Enum.filter(annotations, fn
      %Annotation{layer_id: layer_id} -> MapSet.member?(enabled_layer_ids, layer_id)
      _annotation -> false
    end)
  end

  def select(_annotations, _layer_ids), do: []

  defp layer_ids_from_options(options) when is_map(options) do
    options
    |> attr(:annotation_layers, [])
    |> List.wrap()
    |> normalize_layer_refs()
  end

  defp layer_ids_from_options(_options), do: []

  defp normalize_layer_refs(layer_refs) when is_list(layer_refs) do
    layer_refs
    |> Enum.flat_map(&normalize_layer_ref/1)
    |> Enum.uniq()
  end

  defp normalize_layer_ref(layer_id) when is_binary(layer_id) do
    case String.trim(layer_id) do
      "" -> []
      layer_id -> [layer_id]
    end
  end

  defp normalize_layer_ref(layer_ref) when is_map(layer_ref) do
    enabled? = attr(layer_ref, :enabled, true)

    case {enabled?, attr(layer_ref, :layer_id)} do
      {enabled?, layer_id} when enabled? in [true, "true"] and is_binary(layer_id) ->
        normalize_layer_ref(layer_id)

      _other ->
        []
    end
  end

  defp normalize_layer_ref(_layer_ref), do: []

  defp attr(map, key, default \\ nil) when is_map(map),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))
end
