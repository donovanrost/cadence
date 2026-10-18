defmodule Cadence.Reads.ApplicationSurfaces.Limits.Definitions do
  @moduledoc false
  alias Cadence.Governance
  alias Cadence.Limits
  alias Cadence.Limits.{Definition, DefinitionLifecycle}
  alias Cadence.Ops.PointCatalog
  alias Cadence.Reads.ApplicationSurfaces.Limits.Pages

  def load(org, mission, query) do
    base = "/missions/#{mission}/applications/limits/manage"
    page = Limits.limit_definitions_page(org, mission, page: query["page"], search: query["q"])

    with {:ok, selected} <- selection(org, mission, query, base),
         {:ok, editor} <- editor(org, mission, query, selected) do
      points = points(org, mission, query)

      {:ok,
       %{
         "selection" => selected,
         "editor" => editor,
         "definitions" =>
           Pages.envelope(
             %{page | items: Enum.map(page.items, &row(&1, base, query))},
             base,
             query,
             "page"
           ),
         "points" => Pages.envelope(points, base, query, "points_page")
       }}
    end
  end

  def selection(_, _, %{"definition" => ""}, _), do: {:ok, nil}

  def selection(org, mission, query, base) do
    id = query["definition"]

    with {:ok, current} <- Limits.fetch_latest_limit_definition(org, mission, id),
         {:ok, inspected} <-
           Limits.fetch_limit_definition(org, mission, id, query["version"] || current.version) do
      if query["point"] != "" and query["point"] != inspected.point_id do
        {:error, :invalid_application_surface_query}
      else
        history = Limits.limit_definition_history(org, mission, id, query["history_page"])

        activations =
          DefinitionLifecycle.history_page(
            org,
            mission,
            inspected.point_id,
            inspected.limit_set_name,
            query["activation_page"]
          )

        {:ok,
         %{
           "available" => true,
           "id" => id,
           "current" => definition(current),
           "inspected" => definition(inspected),
           "active" => active(org, inspected),
           "history" =>
             Pages.envelope(
               %{history | items: Enum.map(history.items, &row(&1, base, query))},
               base,
               query,
               "history_page"
             ),
           "activations" =>
             Pages.envelope(
               %{activations | items: Enum.map(activations.items, &activation/1)},
               base,
               query,
               "activation_page"
             )
         }}
      end
    else
      {:error, :limit_definition_not_found} -> {:ok, %{"available" => false, "id" => id}}
    end
  end

  defp editor(_, _, _, %{"available" => false}), do: {:ok, nil}

  defp editor(org, mission, query, %{"available" => true, "inspected" => inspected}) do
    if query["set"] != "" and query["set"] != inspected["limit_set_name"],
      do: {:error, :invalid_application_surface_query},
      else: reviewed_editor(org, mission, inspected["point_id"], inspected["limit_set_name"])
  end

  defp editor(_, _, %{"point" => ""}, nil), do: {:ok, nil}

  defp editor(org, mission, query, nil),
    do:
      reviewed_editor(
        org,
        mission,
        String.trim(query["point"]),
        if(query["set"] == "", do: "DEFAULT", else: String.trim(query["set"]))
      )

  defp reviewed_editor(_org, _mission, "", _set), do: {:error, :invalid_application_surface_query}

  defp reviewed_editor(_org, _mission, _point, ""),
    do: {:error, :invalid_application_surface_query}

  defp reviewed_editor(org, mission, point, set) do
    review = Limits.limit_definition_review(org, mission, point, set)

    current =
      case review.definition_id do
        nil ->
          nil

        id ->
          {:ok, d} = Limits.fetch_limit_definition(org, mission, id, review.version)
          definition(d)
      end

    identity = Definition.new(%{mission_id: mission, point_id: point, limit_set_name: set})

    {:ok,
     %{
       "point_id" => point,
       "limit_set_name" => set,
       "current" => current,
       "active" => active(org, identity),
       "review" => Map.new(review, fn {k, v} -> {to_string(k), v} end)
     }}
  end

  defp points(org, mission, query) do
    raw =
      PointCatalog.list_points(org, mission)
      |> Enum.map(&%{"id" => &1.point_id, "label" => &1.point_id, "kind" => "telemetry"})

    derived =
      Governance.list_derived_definitions(org, mission)
      |> Enum.map(&%{"id" => &1.point_id, "label" => &1.point_name, "kind" => "derived"})

    search = String.downcase(query["points_q"])

    (raw ++ derived)
    |> Enum.uniq_by(& &1["id"])
    |> Enum.sort_by(& &1["id"])
    |> Enum.filter(&String.contains?(String.downcase(&1["id"] <> " " <> &1["label"]), search))
    |> Pages.slice(query["points_page"])
  end

  defp active(org, definition) do
    case DefinitionLifecycle.fetch_active_status_for_definition(definition, organization_id: org) do
      {:ok, status} ->
        %{
          "definition_id" => status.limit_definition_id,
          "version" => status.limit_definition_version,
          "event_id" => status.limit_definition_lifecycle_event_id,
          "active_from" => Pages.stamp(status.active_from),
          "active_to" => Pages.stamp(status.active_to)
        }

      {:error, :active_limit_definition_not_found} ->
        nil
    end
  end

  def definition(d),
    do: %{
      "id" => d.limit_definition_id,
      "point_id" => d.point_id,
      "limit_set_name" => d.limit_set_name,
      "thresholds" => d.thresholds,
      "version" => d.version
    }

  defp row(d, base, query),
    do:
      Map.put(
        definition(d),
        "href",
        Pages.href(
          base,
          query
          |> Map.put("definition", d.limit_definition_id)
          |> Map.put("version", d.version)
          |> Map.put("point", "")
          |> Map.put("set", "")
          |> Map.put("history_page", 1)
          |> Map.put("activation_page", 1)
        )
      )

  defp activation(e),
    do: %{
      "id" => e.limit_definition_lifecycle_event_id,
      "definition_id" => e.limit_definition_id,
      "version" => e.limit_definition_version,
      "event_type" => to_string(e.event_type),
      "active_from" => Pages.stamp(e.active_from),
      "active_to" => Pages.stamp(e.active_to),
      "observed_at" => Pages.stamp(e.observed_at),
      "scope_type" => enum(e.scope_type),
      "scope_ref" => e.scope_ref,
      "realm" => enum(e.realm)
    }

  defp enum(nil), do: nil
  defp enum(value), do: to_string(value)
end
