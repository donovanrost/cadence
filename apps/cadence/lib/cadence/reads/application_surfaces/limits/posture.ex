defmodule Cadence.Reads.ApplicationSurfaces.Limits.Posture do
  @moduledoc false
  alias Cadence.Reads.ApplicationSurfaces.Limits.{Definitions, Pages}
  alias Cadence.Reads.Limits
  alias Cadence.Reads.LimitStateEvidence
  alias Cadence.SpacecraftStore

  def load(org, mission, query) do
    base = "/missions/#{mission}/applications/limits/activity"

    with {:ok, options, label} <- spacecraft(org, mission, query["spacecraft"]),
         {:ok, selected} <- Definitions.selection(org, mission, query, base) do
      severity = if query["severity"] == "", do: nil, else: query["severity"]

      page =
        Limits.latest_states_page(
          org,
          mission,
          options ++ [search: query["q"], severity: severity, page: query["page"]]
        )

      craft = spacecraft_page(org, mission, query)

      {:ok,
       %{
         "states" =>
           Pages.envelope(
             %{page | items: Enum.map(page.items, &state(&1, mission, base, query))},
             base,
             query,
             "page"
           ),
         "counts" => page.counts,
         "spacecraft_filter" => label,
         "selection" => selected,
         "spacecraft" =>
           Pages.envelope(
             %{
               items:
                 Enum.map(craft.items, &%{"id" => &1.spacecraft_id, "label" => &1.display_name}),
               total_count: craft.total_count,
               page: craft.page
             },
             base,
             query,
             "spacecraft_page"
           )
       }}
    end
  end

  defp spacecraft(_, _, ""), do: {:ok, [], "All spacecraft and mission states"}
  defp spacecraft(_, _, "mission"), do: {:ok, [spacecraft_id: nil], "Mission states"}

  defp spacecraft(org, mission, id) do
    with {:ok, craft} <- SpacecraftStore.fetch_spacecraft(org, mission, id),
         do: {:ok, [spacecraft_id: id], craft.display_name}
  end

  defp spacecraft_page(org, mission, query) do
    opts = [page: query["spacecraft_page"], page_size: 25, search: query["spacecraft_q"]]
    page = SpacecraftStore.list_spacecraft_page(org, mission, opts)
    last = max(1, ceil(page.total_count / 25))

    if page.page > last,
      do: SpacecraftStore.list_spacecraft_page(org, mission, Keyword.put(opts, :page, last)),
      else: page
  end

  defp state(e, mission, base, query) do
    definition_href =
      Pages.href(
        base,
        query
        |> Map.put("definition", e.limit_definition_id)
        |> Map.put("version", e.limit_definition_version)
        |> Map.put("point", "")
        |> Map.put("set", "")
        |> Map.put("history_page", 1)
        |> Map.put("activation_page", 1)
      )

    LimitStateEvidence.row(e, mission, definition_href)
  end
end
