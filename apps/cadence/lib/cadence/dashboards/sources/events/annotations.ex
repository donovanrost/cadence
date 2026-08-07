defmodule Cadence.Dashboards.Sources.Events.Annotations do
  @moduledoc """
  Projects event-adapter products into the generic dashboard annotation contract.

  This module is intentionally owned by the events adapter: the dashboard
  kernel does not know what a contact is or how contact records are linked.
  """

  alias Cadence.Dashboards.{Annotation, AnnotationSpan, DataLink, Field, Frame}

  @contact_provider_id "cadence.contacts"
  @contact_layer_id "mission-contacts"
  @source_health_provider_id "cadence.source-health"
  @source_health_layer_id "source-status"
  @minimum_source_health_interval_ms 1_000

  @spec from_frames([Frame.t()]) :: [Annotation.t()]
  def from_frames(frames) when is_list(frames) do
    contact_annotations = Enum.flat_map(frames, &contact_annotations/1)

    source_health_annotations =
      frames
      |> Enum.flat_map(&source_health_events/1)
      |> coalesce_source_health_events()

    (contact_annotations ++ source_health_annotations)
    |> Enum.uniq_by(& &1.annotation_id)
  end

  def from_frames(_frames), do: []

  @spec from_frame(Frame.t()) :: [Annotation.t()]
  def from_frame(%Frame{} = frame) do
    contact_annotations(frame) ++
      (frame |> source_health_events() |> coalesce_source_health_events())
  end

  defp contact_annotations(
         %Frame{source: :events, shape: :intervals, meta: %{product: :contact_intervals}} = frame
       ) do
    starts_at = field_values(frame, "starts_at")
    ends_at = field_values(frame, "ends_at")
    kinds = field_values(frame, "kind")
    statuses = field_values(frame, "status")
    labels = field_values(frame, "label")
    contact_ids = field_values(frame, "contact_id")
    source_event_ids = field_values(frame, "source_event_id")
    links_by_contact_id = contact_links_by_target_id(frame)

    starts_at
    |> Enum.with_index()
    |> Enum.map(fn {start_time, index} ->
      contact_id = Enum.at(contact_ids, index)
      kind = Enum.at(kinds, index)
      status = Enum.at(statuses, index)

      contact_annotation(%{
        contact_id: contact_id,
        kind: kind,
        status: status,
        label: Enum.at(labels, index),
        starts_at: start_time,
        ends_at: Enum.at(ends_at, index),
        source_event_id: Enum.at(source_event_ids, index),
        link: Map.get(links_by_contact_id, contact_id),
        scope: frame.scope,
        frame_id: frame.frame_id,
        source_request_id: Map.get(frame.meta, :source_request_id),
        projection: Map.get(frame.meta, :projection)
      })
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp contact_annotations(%Frame{}), do: []

  defp source_health_events(%Frame{source: :events, shape: :events, meta: meta} = frame)
       when is_map(meta) do
    if Map.get(meta, :family, Map.get(meta, "family")) in [:source_health, "source_health"] do
      occurred_at = field_values(frame, "occurred_at")
      source_event_ids = field_values(frame, "source_record_id")
      source_health_states = field_values(frame, "source_health")
      previous_source_health_states = field_values(frame, "previous_source_health")
      reasons = field_values(frame, "reason")
      logical_sources = field_values(frame, "logical_source")
      data_source_ids = field_values(frame, "data_source_id")
      source_binding_ids = field_values(frame, "source_binding_id")
      realms = field_values(frame, "realm")
      datasets = field_values(frame, "dataset")
      links_by_event_id = source_health_links_by_target_id(frame)

      occurred_at
      |> Enum.with_index()
      |> Enum.map(fn {observed_at, index} ->
        source_event_id = Enum.at(source_event_ids, index)

        %{
          observed_at: observed_at,
          source_event_id: source_event_id,
          source_health: text(Enum.at(source_health_states, index)),
          previous_source_health: text(Enum.at(previous_source_health_states, index)),
          reason: text(Enum.at(reasons, index)),
          logical_source: text(Enum.at(logical_sources, index)),
          data_source_id: Enum.at(data_source_ids, index),
          source_binding_id: Enum.at(source_binding_ids, index),
          realm: text(Enum.at(realms, index)),
          dataset: Enum.at(datasets, index),
          link: Map.get(links_by_event_id, source_event_id),
          scope: frame.scope,
          frame_id: frame.frame_id,
          source_request_id: Map.get(frame.meta, :source_request_id),
          projection: Map.get(frame.meta, :projection)
        }
      end)
      |> Enum.filter(&valid_source_health_event?/1)
    else
      []
    end
  end

  defp source_health_events(%Frame{}), do: []

  defp coalesce_source_health_events(events) when is_list(events) do
    events
    |> Enum.group_by(&source_health_identity/1)
    |> Enum.flat_map(fn {_identity, identity_events} ->
      identity_events
      |> Enum.sort_by(&DateTime.to_unix(&1.observed_at, :microsecond))
      |> coalesce_source_health_identity()
    end)
    |> Enum.sort_by(&DateTime.to_unix(&1.span.starts_at, :microsecond))
  end

  defp coalesce_source_health_events(_events), do: []

  defp coalesce_source_health_identity(events) do
    {open_event, annotations} =
      Enum.reduce(events, {nil, []}, fn event, {open_event, annotations} ->
        cond do
          unhealthy_source_state?(event.source_health) and is_nil(open_event) ->
            {event, annotations}

          unhealthy_source_state?(event.source_health) ->
            {more_severe_event(open_event, event), annotations}

          healthy_source_state?(event.source_health) and is_map(open_event) ->
            {nil, maybe_append_source_health_annotation(annotations, open_event, event)}

          true ->
            {open_event, annotations}
        end
      end)

    annotations =
      if is_map(open_event) do
        maybe_append_source_health_annotation(annotations, open_event, nil)
      else
        annotations
      end

    Enum.reverse(annotations)
  end

  defp maybe_append_source_health_annotation(annotations, opened, recovered) do
    case source_health_annotation(opened, recovered) do
      %Annotation{} = annotation -> [annotation | annotations]
      nil -> annotations
    end
  end

  defp source_health_annotation(opened, recovered) do
    duration_ms = source_health_duration_ms(opened, recovered)

    if is_nil(recovered) or duration_ms >= @minimum_source_health_interval_ms do
      logical_source = opened.logical_source || "data"
      source_health = opened.source_health || "degraded"

      Annotation.new(%{
        annotation_id:
          Enum.join(
            [@source_health_provider_id, "outage", opened.source_event_id],
            ":"
          ),
        provider_id: @source_health_provider_id,
        layer_id: @source_health_layer_id,
        kind: "source_health_outage",
        span: %AnnotationSpan{
          kind: :interval,
          starts_at: opened.observed_at,
          ends_at: recovered && recovered.observed_at
        },
        title: "#{humanize(logical_source)} source #{humanize(source_health)}",
        text: source_health_text(logical_source, source_health, duration_ms, is_nil(recovered)),
        tags: tags(["source-health", logical_source, source_health]),
        severity: source_health_severity(source_health),
        style: %{
          primitive: :rail,
          color: source_health_color(source_health),
          lane: "data-quality",
          glyph: "SOURCE"
        },
        link: annotation_link(opened.link),
        scope: opened.scope || %{},
        provenance: %{
          frame_id: opened.frame_id,
          source_request_id: opened.source_request_id,
          projection: opened.projection,
          source_event_id: opened.source_event_id,
          recovery_event_id: recovered && recovered.source_event_id
        },
        metadata: %{
          active?: is_nil(recovered),
          duration_ms: duration_ms,
          logical_source: logical_source,
          data_source_id: opened.data_source_id,
          source_binding_id: opened.source_binding_id,
          realm: opened.realm,
          dataset: opened.dataset,
          source_health: source_health,
          previous_source_health: opened.previous_source_health,
          reason: opened.reason,
          recovery_event_id: recovered && recovered.source_event_id
        }
      })
    end
  end

  defp valid_source_health_event?(event) do
    match?(%DateTime{}, event.observed_at) and present_text?(event.source_event_id) and
      present_text?(event.source_health)
  end

  defp source_health_identity(event) do
    {
      event.logical_source,
      event.data_source_id,
      event.source_binding_id,
      event.realm,
      event.dataset
    }
  end

  defp more_severe_event(opened, event) do
    if source_health_rank(event.source_health) > source_health_rank(opened.source_health) do
      %{
        event
        | observed_at: opened.observed_at,
          source_event_id: opened.source_event_id,
          link: opened.link
      }
    else
      opened
    end
  end

  defp source_health_rank("unavailable"), do: 3
  defp source_health_rank("degraded"), do: 2
  defp source_health_rank("unknown"), do: 1
  defp source_health_rank(_state), do: 0

  defp unhealthy_source_state?(state), do: state in ["unavailable", "degraded", "unknown"]
  defp healthy_source_state?(state), do: state == "healthy"

  defp source_health_duration_ms(_opened, nil), do: nil

  defp source_health_duration_ms(opened, recovered) do
    DateTime.diff(recovered.observed_at, opened.observed_at, :millisecond)
  end

  defp source_health_text(logical_source, source_health, _duration_ms, true) do
    "#{humanize(logical_source)} source is currently #{humanize(source_health)}"
  end

  defp source_health_text(logical_source, source_health, duration_ms, false) do
    "#{humanize(logical_source)} source was #{humanize(source_health)} for #{duration_ms} ms"
  end

  defp source_health_severity("unavailable"), do: :error
  defp source_health_severity(_source_health), do: :warning

  defp source_health_color("unavailable"), do: "red"
  defp source_health_color(_source_health), do: "amber"

  defp humanize(value) when is_binary(value) do
    value
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp contact_annotation(
         %{
           contact_id: contact_id,
           starts_at: %DateTime{} = starts_at
         } = attrs
       )
       when is_binary(contact_id) and contact_id != "" do
    kind = text(Map.get(attrs, :kind))
    status = text(Map.get(attrs, :status))

    {span, span_normalization} =
      contact_span(starts_at, Map.get(attrs, :ends_at), status)

    Annotation.new(%{
      annotation_id: Enum.join([@contact_provider_id, kind || "contact", contact_id], ":"),
      provider_id: @contact_provider_id,
      layer_id: @contact_layer_id,
      kind: "contact_interval",
      span: span,
      title: Map.get(attrs, :label) || "Contact #{contact_id}",
      tags: tags(["contact", kind, status]),
      severity: contact_severity(status),
      style: %{primitive: :rail, color: "cyan", lane: "operations", glyph: "CONTACT"},
      link: annotation_link(Map.get(attrs, :link)),
      scope: Map.get(attrs, :scope) || %{},
      provenance: %{
        frame_id: Map.get(attrs, :frame_id),
        source_request_id: Map.get(attrs, :source_request_id),
        projection: Map.get(attrs, :projection),
        source_event_id: Map.get(attrs, :source_event_id)
      },
      metadata:
        %{
          contact_id: contact_id,
          contact_kind: kind,
          status: status
        }
        |> maybe_put_span_normalization(span_normalization)
    })
  end

  defp contact_annotation(_attrs), do: nil

  defp contact_span(starts_at, ends_at, status)
       when status in ["active", "in_progress", "running"] do
    normalization =
      if match?(%DateTime{}, ends_at), do: "active_contact_end_ignored", else: nil

    {%AnnotationSpan{kind: :interval, starts_at: starts_at, ends_at: nil}, normalization}
  end

  defp contact_span(starts_at, %DateTime{} = ends_at, _status) do
    case DateTime.compare(starts_at, ends_at) do
      order when order in [:lt, :eq] ->
        {%AnnotationSpan{kind: :interval, starts_at: starts_at, ends_at: ends_at}, nil}

      :gt ->
        {%AnnotationSpan{kind: :point, starts_at: starts_at, ends_at: nil}, "ends_before_start"}
    end
  end

  defp contact_span(starts_at, nil, _status) do
    {%AnnotationSpan{kind: :interval, starts_at: starts_at, ends_at: nil}, nil}
  end

  defp contact_span(starts_at, _ends_at, _status) do
    {%AnnotationSpan{kind: :point, starts_at: starts_at, ends_at: nil}, "invalid_end"}
  end

  defp maybe_put_span_normalization(metadata, nil), do: metadata

  defp maybe_put_span_normalization(metadata, normalization) do
    Map.put(metadata, :span_normalization, normalization)
  end

  defp field_values(%Frame{fields: fields}, name) do
    case Enum.find(fields, &match?(%Field{name: ^name}, &1)) do
      %Field{values: values} when is_list(values) -> values
      _field -> []
    end
  end

  defp contact_links_by_target_id(%Frame{meta: meta}) when is_map(meta) do
    meta
    |> Map.get(:links, [])
    |> Enum.filter(&match?(%DataLink{target: :contact}, &1))
    |> Map.new(&{&1.target_id, &1})
  end

  defp contact_links_by_target_id(%Frame{}), do: %{}

  defp source_health_links_by_target_id(%Frame{meta: meta}) when is_map(meta) do
    meta
    |> Map.get(:links, [])
    |> Enum.filter(&match?(%DataLink{target: :source_health_event}, &1))
    |> Map.new(&{&1.target_id, &1})
  end

  defp source_health_links_by_target_id(%Frame{}), do: %{}

  defp annotation_link(%DataLink{} = link), do: %DataLink{link | source: :annotation}
  defp annotation_link(_link), do: nil

  defp contact_severity(status) when status in ["failed", "aborted"], do: :error
  defp contact_severity(status) when status in ["canceled", "cancelled", "missed"], do: :warning
  defp contact_severity(_status), do: :info

  defp tags(values), do: values |> Enum.filter(&present_text?/1) |> Enum.uniq()

  defp text(value) when is_atom(value), do: Atom.to_string(value)
  defp text(value) when is_binary(value) and value != "", do: value
  defp text(_value), do: nil

  defp present_text?(value), do: is_binary(value) and value != ""
end
