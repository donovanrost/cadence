defmodule Cadence.Dashboards.AuthoringWidget do
  @moduledoc "Applies widget form edits without erasing unedited authored semantics."
  alias Cadence.Dashboards.{Document, Placement, PlacementEditor, WidgetDef}

  def defaults, do: PlacementEditor.form_defaults() |> Map.delete("point_q")

  def fields(%Placement{} = placement),
    do: PlacementEditor.to_form_params(placement) |> Map.delete("point_q")

  def observables(placement), do: PlacementEditor.selected_observables(placement)

  def build(%Document{} = document, fields, observables, existing) do
    panel = if existing, do: {:edit_placement, existing.placement_id}, else: :add_widget

    with :ok <- editable(existing),
         :ok <- observable_count(fields, observables),
         {:ok, candidate} <-
           PlacementEditor.build_placement(fields, observables, panel, existing,
             organization_id: document.organization_id,
             mission_id: document.mission_id,
             authoring_scope_context: authoring_scope(document, fields)
           ),
         candidate <- multi_series(candidate, fields, observables) do
      {:ok, merge(existing, candidate, fields, observables)}
    end
  end

  defp authoring_scope(_document, %{"mode" => "fixed", "spacecraft_id" => id}),
    do: %{primary: %{kind: "spacecraft", mode: "one", ids: [id]}}

  defp authoring_scope(_document, %{"mode" => "scope", "scope_kind" => kind, "scope_id" => id}),
    do: %{primary: %{kind: kind, mode: "one", ids: [id]}}

  defp authoring_scope(_document, %{"mode" => "repeat", "repeat_over" => kind}),
    do: %{primary: %{kind: kind, mode: "each", ids: []}}

  defp authoring_scope(document, _fields),
    do: Map.get(document.defaults, :scope, Map.get(document.defaults, "scope"))

  defp editable(nil), do: :ok

  defp editable(
         %Placement{content_kind: :embedded, widget_def: %WidgetDef{widget_type_version: 1}} =
           placement
       ) do
    if fields(placement)["type"] != "", do: :ok, else: {:error, :unsupported_widget}
  end

  defp editable(_), do: {:error, :unsupported_widget}

  defp observable_count(%{"type" => type, "binding_source" => source}, values) do
    if valid_observable_count?(type, length(values)) and valid_source?(type, source),
      do: :ok,
      else: {:error, :invalid_widget}
  end

  defp valid_observable_count?(type, count) when type in ~w(event_timeline constellation_health),
    do: count == 0

  defp valid_observable_count?(type, count) when type in ~w(value_tile state_timeline),
    do: count == 1

  defp valid_observable_count?("time_series", count), do: count in 1..8
  defp valid_observable_count?(_type, count), do: count in 1..24

  defp valid_source?(type, _source) when type in ~w(event_timeline constellation_health), do: true

  defp valid_source?("state_timeline", source),
    do: source in ~w(telemetry limits operational_observables)

  defp valid_source?(_type, source), do: source in ~w(telemetry operational_observables)

  # The legacy form builder selects only one telemetry observable for a chart;
  # the canonical chart contract supports up to eight. Do not drop the others.
  defp multi_series(candidate, %{"type" => "time_series"}, observables),
    do: %{
      candidate
      | widget_def: %{
          candidate.widget_def
          | binding: Map.put(candidate.widget_def.binding, :observables, observables)
        }
    }

  defp multi_series(candidate, _, _), do: candidate

  defp merge(nil, candidate, _fields, _observables), do: candidate

  defp merge(existing, candidate, next_fields, next_observables) do
    previous = fields(existing)
    changed? = fn keys -> Enum.any?(keys, &(previous[&1] != next_fields[&1])) end
    type_changed? = changed?.(["type"])
    binding = binding(existing, candidate, next_observables, changed?)

    options =
      Enum.reduce(candidate.widget_def.options, existing.widget_def.options, fn {key, value},
                                                                                acc ->
        if type_changed? or changed?.([Atom.to_string(key)]),
          do: acc |> Map.delete(Atom.to_string(key)) |> Map.put(key, value),
          else: acc
      end)

    %{
      existing
      | section_id: candidate.section_id,
        widget_def: %{
          existing.widget_def
          | widget_type_id: candidate.widget_def.widget_type_id,
            title: candidate.widget_def.title,
            binding: binding,
            options: options
        },
        scope_override:
          if(changed?.(~w(type mode spacecraft_id scope_kind scope_id)),
            do: candidate.scope_override,
            else: existing.scope_override
          ),
        repeat:
          if(changed?.(~w(type mode repeat_over repeat_layout repeat_max_instances)),
            do: candidate.repeat,
            else: existing.repeat
          )
    }
  end

  defp binding(existing, candidate, next_observables, changed?) do
    if changed?.(~w(type binding_source)) do
      candidate.widget_def.binding
    else
      binding = existing.widget_def.binding

      binding =
        if observables(existing) == next_observables,
          do: binding,
          else: Map.put(binding, :observables, next_observables)

      if changed?.(["mode"]),
        do: Map.put(binding, :scope_mode, candidate.widget_def.binding.scope_mode),
        else: binding
    end
  end
end
