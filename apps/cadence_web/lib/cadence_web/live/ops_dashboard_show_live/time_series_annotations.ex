defmodule CadenceWeb.OpsDashboardShowLive.TimeSeriesAnnotations do
  @moduledoc """
  Serializes normalized dashboard annotations for the generic chart renderer.

  This boundary is deliberately domain-agnostic. Provider-owned metadata is
  passed through, while geometry and evidence navigation use one stable payload.
  """

  alias Cadence.Dashboards.{Annotation, AnnotationSpan, DataLink, PlacementFrames}

  @spec annotations(PlacementFrames.t() | nil) :: [map()]
  def annotations(%PlacementFrames{annotations: annotations}) when is_list(annotations) do
    annotations
    |> Enum.map(&annotation_payload/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.annotation_id)
  end

  def annotations(_placement_frames), do: []

  defp annotation_payload(
         %Annotation{
           span: %AnnotationSpan{starts_at: %DateTime{} = starts_at} = span
         } = annotation
       ) do
    link = annotation.link

    %{
      annotation_id: annotation.annotation_id,
      provider_id: annotation.provider_id,
      layer_id: annotation.layer_id,
      annotation_kind: annotation.kind,
      geometry: Atom.to_string(span.kind),
      starts_at_ms: DateTime.to_unix(starts_at, :millisecond),
      ends_at_ms: timestamp_ms(span.ends_at),
      timestamp_ms: if(span.kind == :point, do: DateTime.to_unix(starts_at, :millisecond)),
      title: annotation.title,
      text: annotation.text,
      tags: annotation.tags,
      severity: Atom.to_string(annotation.severity),
      primitive: style_value(annotation.style, :primitive),
      color: style_value(annotation.style, :color),
      lane: style_value(annotation.style, :lane),
      glyph: style_value(annotation.style, :glyph),
      link_id: link_value(link, :link_id),
      target: link_value(link, :target),
      target_id: link_value(link, :target_id),
      metadata: annotation.metadata
    }
    |> Map.merge(source_request_context(annotation.provenance))
    |> drop_nil_values()
  end

  defp annotation_payload(_annotation), do: nil

  defp timestamp_ms(%DateTime{} = datetime), do: DateTime.to_unix(datetime, :millisecond)
  defp timestamp_ms(_datetime), do: nil

  defp link_value(%DataLink{} = link, key), do: Map.get(link, key)
  defp link_value(_link, _key), do: nil

  defp style_value(style, key) when is_map(style) do
    case Map.get(style, key, Map.get(style, Atom.to_string(key))) do
      value when is_atom(value) -> Atom.to_string(value)
      value -> value
    end
  end

  defp style_value(_style, _key), do: nil

  defp source_request_context(provenance) when is_map(provenance) do
    case Map.get(provenance, :source_request_context) do
      context when is_map(context) -> context
      _context -> %{}
    end
  end

  defp source_request_context(_provenance), do: %{}

  defp drop_nil_values(map) do
    map
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end
end
