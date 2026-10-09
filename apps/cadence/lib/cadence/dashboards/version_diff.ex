defmodule Cadence.Dashboards.VersionDiff do
  @moduledoc """
  Human-readable differences between two dashboard documents, for the save
  dialog ("what am I about to save?") and version comparison ("what changed
  between v3 and v7?"). Mirrors Grafana's summary list: one entry per changed
  thing, ordered dashboard → sections → widgets, never a raw JSON patch.
  """
  alias Cadence.Dashboards.{Document, Placement, Section, WidgetDef}

  @type change :: %{
          kind: String.t(),
          subject: String.t(),
          label: String.t(),
          detail: String.t() | nil
        }

  @spec changes(Document.t(), Document.t()) :: [change()]
  def changes(%Document{} = from, %Document{} = to) do
    dashboard(from, to) ++ sections(from, to) ++ widgets(from, to)
  end

  defp dashboard(from, to) do
    [
      if(from.name != to.name,
        do: change("changed", "dashboard", "Renamed dashboard", "#{from.name} → #{to.name}")
      ),
      if(from.description != to.description,
        do: change("changed", "dashboard", "Changed description", nil)
      ),
      if(from.defaults != to.defaults,
        do: change("changed", "dashboard", "Changed runtime defaults", nil)
      ),
      if(from.grid != to.grid, do: change("changed", "dashboard", "Changed grid settings", nil))
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp sections(from, to) do
    before = Map.new(from.sections, &{&1.section_id, &1})
    after_ = Map.new(to.sections, &{&1.section_id, &1})

    added = for %Section{} = s <- to.sections, not Map.has_key?(before, s.section_id), do: s
    removed = for %Section{} = s <- from.sections, not Map.has_key?(after_, s.section_id), do: s

    changed =
      for %Section{} = s <- to.sections,
          %Section{} = old <- [Map.get(before, s.section_id)],
          old != s,
          do: change("changed", "section", "Changed section “#{s.title}”", section_detail(old, s))

    reordered =
      if ids(from.sections, :section_id) -- removed_ids(removed) !=
           ids(to.sections, :section_id) -- added_ids(added),
         do: [change("changed", "section", "Reordered sections", nil)],
         else: []

    Enum.map(added, &change("added", "section", "Added section “#{&1.title}”", nil)) ++
      Enum.map(removed, &change("removed", "section", "Removed section “#{&1.title}”", nil)) ++
      changed ++ reordered
  end

  defp section_detail(old, new) do
    cond do
      old.title != new.title -> "#{old.title} → #{new.title}"
      old.collapsed_by_default? != new.collapsed_by_default? -> "Collapsed by default"
      true -> "Description"
    end
  end

  defp widgets(from, to) do
    before = Map.new(from.placements, &{&1.placement_id, &1})
    after_ = Map.new(to.placements, &{&1.placement_id, &1})

    added =
      for %Placement{} = p <- to.placements,
          not Map.has_key?(before, p.placement_id),
          do: change("added", "widget", "Added widget “#{title(p)}”", type(p))

    removed =
      for %Placement{} = p <- from.placements,
          not Map.has_key?(after_, p.placement_id),
          do: change("removed", "widget", "Removed widget “#{title(p)}”", nil)

    common =
      for %Placement{} = p <- to.placements,
          %Placement{} = old <- [Map.get(before, p.placement_id)],
          do: {old, p}

    edited =
      for {old, new} <- common,
          detail = widget_detail(old, new),
          detail != nil,
          do: change("changed", "widget", "Changed widget “#{title(new)}”", detail)

    moved = Enum.count(common, fn {old, new} -> layout(old) != layout(new) end)

    layout_change =
      if moved > 0,
        do: [change("changed", "layout", "Moved or resized #{plural(moved, "widget")}", nil)],
        else: []

    added ++ removed ++ edited ++ layout_change
  end

  defp widget_detail(%Placement{} = old, %Placement{} = new) do
    title =
      if widget_title(old) != widget_title(new),
        do: ["title #{widget_title(old)} → #{widget_title(new)}"],
        else: []

    aspects = for {label, read} <- widget_aspects(), read.(old) != read.(new), do: label

    case title ++ aspects do
      [] -> nil
      parts -> Enum.join(parts, ", ")
    end
  end

  # Each aspect of a widget an author can change, compared independently.
  defp widget_aspects do
    [
      {"visualization", &definition(&1, :widget_type_id)},
      {"data binding", &definition(&1, :binding)},
      {"display options", &definition(&1, :options)},
      {"section", & &1.section_id},
      {"scope", &{&1.repeat, &1.scope_override, &1.data_override, &1.limit_override}},
      {"library source", &{&1.library_widget_id, &1.library_version, &1.overrides}}
    ]
  end

  defp widget_title(placement), do: definition(placement, :title)
  defp definition(%Placement{widget_def: nil}, _key), do: nil
  defp definition(%Placement{widget_def: definition}, key), do: Map.get(definition, key)

  defp layout(%Placement{layout: layout}), do: Map.take(layout || %{}, [:x, :y, :w, :h])
  defp title(%Placement{widget_def: %WidgetDef{title: title}}) when is_binary(title), do: title
  defp title(%Placement{library_widget_id: id}) when is_binary(id), do: "Library widget"
  defp title(%Placement{placement_id: id}), do: id

  defp type(%Placement{widget_def: %WidgetDef{widget_type_id: id}}) when not is_nil(id),
    do: to_string(id) |> String.replace("_", " ")

  defp type(_), do: nil

  defp ids(list, key), do: Enum.map(list, &Map.fetch!(&1, key))
  defp removed_ids(sections), do: ids(sections, :section_id)
  defp added_ids(sections), do: ids(sections, :section_id)
  defp plural(1, noun), do: "1 #{noun}"
  defp plural(n, noun), do: "#{n} #{noun}s"

  defp change(kind, subject, label, detail),
    do: %{kind: kind, subject: subject, label: label, detail: detail}
end
