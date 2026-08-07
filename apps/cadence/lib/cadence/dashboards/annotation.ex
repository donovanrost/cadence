defmodule Cadence.Dashboards.Annotation do
  @moduledoc """
  Normalized temporal context contributed by a dashboard source adapter.

  Provider and layer identifiers are durable strings. Domain meaning stays in
  adapter-owned tags and metadata while the dashboard kernel consumes only time
  geometry, presentation hints, and an optional evidence link.
  """

  alias Cadence.Dashboards.{AnnotationSpan, DataLink}
  alias Cadence.Platform.ContractNormalization

  @severities [:info, :warning, :error, :critical]
  @primitives [:line, :rail, :region]

  @type t :: %__MODULE__{
          annotation_id: binary(),
          provider_id: binary(),
          layer_id: binary(),
          kind: binary() | nil,
          span: AnnotationSpan.t(),
          title: binary(),
          text: binary() | nil,
          tags: [binary()],
          severity: :info | :warning | :error | :critical,
          style: map(),
          link: DataLink.t() | nil,
          scope: map(),
          provenance: map(),
          metadata: map()
        }

  defstruct [
    :annotation_id,
    :provider_id,
    :layer_id,
    :kind,
    :span,
    :title,
    :text,
    :link,
    tags: [],
    severity: :info,
    style: %{},
    scope: %{},
    provenance: %{},
    metadata: %{}
  ]

  @spec severities() :: [atom()]
  def severities, do: @severities

  @spec primitives() :: [atom()]
  def primitives, do: @primitives

  @spec new(map() | t()) :: t()
  def new(attrs), do: normalize(attrs)

  @spec normalize(map() | t()) :: t() | nil
  def normalize(%__MODULE__{} = annotation) do
    %__MODULE__{
      annotation
      | span: AnnotationSpan.normalize(annotation.span),
        tags: ContractNormalization.binary_list(annotation.tags),
        severity: ContractNormalization.known_atom(annotation.severity, @severities),
        style: normalize_style(annotation.style),
        link: normalize_link(annotation.link),
        scope: ContractNormalization.map_or_default(annotation.scope),
        provenance: ContractNormalization.map_or_default(annotation.provenance),
        metadata: ContractNormalization.map_or_default(annotation.metadata)
    }
  end

  def normalize(annotation) when is_map(annotation) do
    %__MODULE__{
      annotation_id: ContractNormalization.attr(annotation, :annotation_id),
      provider_id: ContractNormalization.attr(annotation, :provider_id),
      layer_id: ContractNormalization.attr(annotation, :layer_id),
      kind: ContractNormalization.attr(annotation, :kind),
      span: annotation |> ContractNormalization.attr(:span) |> AnnotationSpan.normalize(),
      title: ContractNormalization.attr(annotation, :title),
      text: ContractNormalization.attr(annotation, :text),
      tags:
        annotation
        |> ContractNormalization.attr(:tags, [])
        |> ContractNormalization.binary_list(),
      severity:
        annotation
        |> ContractNormalization.attr(:severity, :info)
        |> ContractNormalization.known_atom(@severities),
      style:
        annotation
        |> ContractNormalization.attr(:style, %{})
        |> normalize_style(),
      link: annotation |> ContractNormalization.attr(:link) |> normalize_link(),
      scope:
        annotation
        |> ContractNormalization.attr(:scope, %{})
        |> ContractNormalization.map_or_default(),
      provenance:
        annotation
        |> ContractNormalization.attr(:provenance, %{})
        |> ContractNormalization.map_or_default(),
      metadata:
        annotation
        |> ContractNormalization.attr(:metadata, %{})
        |> ContractNormalization.map_or_default()
    }
  end

  def normalize(_annotation), do: nil

  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{} = annotation) do
    present_text?(annotation.annotation_id) and
      present_text?(annotation.provider_id) and
      present_text?(annotation.layer_id) and
      present_text?(annotation.title) and
      match?(%AnnotationSpan{}, annotation.span) and
      AnnotationSpan.valid?(annotation.span) and
      annotation.severity in @severities and
      valid_primitive?(annotation.style)
  end

  defp normalize_style(style) when is_map(style) do
    primitive =
      style
      |> ContractNormalization.attr(:primitive)
      |> ContractNormalization.known_atom(@primitives)

    style
    |> ContractNormalization.map_or_default()
    |> maybe_put_primitive(primitive)
  end

  defp normalize_style(nil), do: %{}
  defp normalize_style(style), do: style

  defp normalize_link(nil), do: nil
  defp normalize_link(link), do: DataLink.normalize(link) || link

  defp maybe_put_primitive(style, nil), do: style
  defp maybe_put_primitive(style, primitive), do: Map.put(style, :primitive, primitive)

  defp valid_primitive?(style) when is_map(style) do
    case ContractNormalization.attr(style, :primitive) do
      nil -> true
      primitive -> primitive in @primitives
    end
  end

  defp valid_primitive?(_style), do: false

  defp present_text?(value), do: is_binary(value) and value != ""
end
