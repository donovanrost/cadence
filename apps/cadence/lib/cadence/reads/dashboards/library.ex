defmodule Cadence.Reads.Dashboards.Library do
  @moduledoc "Authorized library metadata, selected immutable definitions and current-draft consumers."
  alias Cadence.Dashboards.{Authoring, Document, Documents, LibraryInput, LibraryStore}

  def load(scope, mission, params \\ %{}) do
    with :ok <- Authoring.authorize(scope, mission),
         {:ok, query} <- LibraryInput.query(params),
         {:ok, target} <- target(scope, mission, query.target_id),
         {:ok, data} <- LibraryStore.load(scope.organization_id, mission, query),
         {:ok, selected} <- selected(data.selected, data.consumers) do
      {:ok,
       %{
         version: 1,
         organization_id: scope.organization_id,
         mission_id: mission,
         query: query,
         items: Enum.map(data.items, &item/1),
         next_item: data.next_item,
         selected: selected,
         dashboards: Enum.map(data.dashboards, &dashboard/1),
         next_dashboard: data.next_dashboard,
         target: target
       }}
    else
      _ -> {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  catch
    _, _ -> {:error, :unavailable}
  end

  defp target(_, _, nil), do: {:ok, nil}

  defp target(scope, mission, id) do
    with {:ok, document} <- Documents.fetch_for_mode(scope.organization_id, mission, id, :edit),
         do:
           {:ok,
            %{id: document.dashboard_id, name: document.name, version: Document.version(document)}}
  end

  defp selected(nil, _), do: {:ok, nil}

  defp selected(selected, consumers) do
    with {:ok, json} <- LibraryInput.encode(selected.version.widget_definition) do
      {:ok,
       %{
         item: item(selected.item),
         version: selected.version.version,
         widget_json: json,
         versions:
           Enum.map(selected.versions, fn v ->
             %{
               version: v.version,
               summary: v.change_summary || "",
               actor_id: v.created_by,
               saved_at: timestamp(v.inserted_at)
             }
           end),
         next_version: selected.next_version,
         consumers: %{
           total: consumers.total,
           next: consumers.next,
           rows:
             Enum.map(consumers.rows, fn row ->
               Map.put(
                 dashboard(row),
                 :pins,
                 Enum.map(row.pins, fn pin ->
                   %{id: pin["placement_id"], version: pin["content"]["library_version"]}
                 end)
               )
             end)
         }
       }}
    end
  end

  defp item(row),
    do: %{
      id: row.dashboard_library_item_id,
      name: row.name,
      description: row.description || "",
      latest_version: row.latest_version
    }

  defp dashboard(row), do: %{id: row.dashboard_id, name: row.name, version: row.latest_version}
  defp timestamp(nil), do: nil
  defp timestamp(value), do: DateTime.to_iso8601(value)
end
