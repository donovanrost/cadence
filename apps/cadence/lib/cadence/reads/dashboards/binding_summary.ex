defmodule Cadence.Reads.Dashboards.BindingSummary do
  @moduledoc """
  Which spacecraft a dashboard shows, for the directory's Spacecraft column (ux Q4), from its
  current document:

  - `nil`: no widgets.
  - `%{mode: "fleet"}`: every widget is constellation-wide (`cadence.constellation_health`).
  - `%{mode: "fixed", spacecraft: %{id, name}}`: every other widget is bound to the same
    spacecraft (the document's default scope or the widget's own override).
  - `%{mode: "context"}`: no widget names a spacecraft; the viewer picks one.
  - `%{mode: "mixed"}`: anything else (different spacecraft, or some fixed and some chosen).

  Constellation-wide widgets don't change the answer when other widgets exist. Library
  placements count as bound by scope like any other widget.
  """

  alias Cadence.Dashboards.{Document, Documents, Placement, WidgetDef}
  alias Cadence.SpacecraftStore

  @fleet_widgets ~w(cadence.constellation_health constellation_health)

  @doc "Binding summaries for these dashboards, by id (`nil` when unreadable or empty)."
  @spec load(binary(), binary(), [binary()]) :: %{binary() => map() | nil}
  def load(org, mission, dashboard_ids) do
    ids = Enum.uniq(dashboard_ids)

    names =
      if ids == [],
        do: %{},
        else:
          Map.new(
            SpacecraftStore.list_spacecraft(org, mission),
            &{&1.spacecraft_id, &1.display_name || &1.spacecraft_id}
          )

    Map.new(ids, &{&1, org |> document(mission, &1) |> summarize(names)})
  end

  @doc false
  @spec summarize(Document.t() | nil, %{binary() => binary()}) :: map() | nil
  def summarize(nil, _names), do: nil
  def summarize(%Document{placements: []}, _names), do: nil

  def summarize(%Document{} = document, names) do
    default = spacecraft_id(scope(document.defaults))

    bound =
      document.placements
      |> Enum.reject(&fleet?/1)
      |> Enum.map(&(spacecraft_id(&1.scope_override) || default))

    case Enum.uniq(bound) do
      [] -> %{mode: "fleet"}
      [nil] -> %{mode: "context"}
      [id] -> %{mode: "fixed", spacecraft: %{id: id, name: Map.get(names, id, id)}}
      _several -> %{mode: "mixed"}
    end
  end

  # The current version; an archived dashboard's latest.
  defp document(org, mission, id) do
    case Documents.fetch_published(org, mission, id) do
      {:ok, %Document{} = document} ->
        document

      _not_current ->
        case Documents.fetch(org, mission, id) do
          {:ok, %Document{} = document} -> document
          _missing -> nil
        end
    end
  rescue
    _unreadable -> nil
  end

  defp fleet?(%Placement{widget_def: %WidgetDef{widget_type_id: type}}),
    do: type in @fleet_widgets

  defp fleet?(%Placement{}), do: false

  defp scope(defaults) when is_map(defaults),
    do: Map.get(defaults, "scope") || Map.get(defaults, :scope)

  defp scope(_defaults), do: nil

  defp spacecraft_id(scope) when is_map(scope) do
    case Map.get(scope, :spacecraft_id) || Map.get(scope, "spacecraft_id") do
      id when is_binary(id) and id != "" -> id
      _none -> nil
    end
  end

  defp spacecraft_id(_scope), do: nil
end
