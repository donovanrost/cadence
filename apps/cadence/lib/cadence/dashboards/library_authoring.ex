defmodule Cadence.Dashboards.LibraryAuthoring do
  @moduledoc "Authorized immutable library version creation and exact-version draft placement."
  alias Cadence.Dashboards.{Authoring, Document, Documents, LibraryInput, Management, Placement}

  def execute(scope, mission, event, input) do
    with :ok <- Authoring.authorize(scope, mission),
         {:ok, command} <- LibraryInput.admit(event, input) do
      effect(scope, mission, event, command)
    else
      error -> normalize(error)
    end
  rescue
    _ -> {:error, :unknown}
  catch
    _, _ -> {:error, :unknown}
  end

  defp effect(scope, mission, "create_item", command) do
    attrs =
      Map.take(command, ~w(name description change_summary widget_definition))
      |> Map.update!("name", &String.trim/1)

    case Management.create_library_item(scope.organization_id, mission, attrs,
           created_by: scope.user.user_id
         ) do
      {:ok, item} -> {:ok, receipt("create_item", item.dashboard_library_item_id, 1)}
      error -> normalize(error)
    end
  end

  defp effect(scope, mission, "add_version", command) do
    case Management.add_library_version(
           scope.organization_id,
           mission,
           command["item_id"],
           command["widget_definition"],
           expected_version: command["expected_version"],
           change_summary: command["change_summary"],
           created_by: scope.user.user_id
         ) do
      {:ok, item} ->
        {:ok, receipt("add_version", item.dashboard_library_item_id, item.latest_version)}

      error ->
        normalize(error)
    end
  end

  defp effect(scope, mission, "add_to_draft", command) do
    with {:ok, _version} <-
           Management.fetch_library_version(
             scope.organization_id,
             mission,
             command["item_id"],
             command["version"]
           ),
         {:ok, document} <-
           Documents.fetch_for_mode(
             scope.organization_id,
             mission,
             command["dashboard_id"],
             :edit
           ),
         :ok <- observed(document, command["expected_version"]),
         true <- length(document.placements) < 1024 do
      placement = %Placement{
        placement_id: Cadence.Ids.new("dash_placement"),
        content_kind: :library,
        library_widget_id: command["item_id"],
        library_version: command["version"],
        layout: %{x: nil, y: nil, w: min(4, document.grid.columns), h: 2}
      }

      save_placement(scope, document, placement, command)
    else
      false -> {:error, :capacity}
      error -> normalize(error)
    end
  end

  defp save_placement(scope, document, placement, command) do
    case Documents.update(
           scope.organization_id,
           document.mission_id,
           document.dashboard_id,
           Document.put_placement(document, placement),
           expected_version: command["expected_version"],
           created_by: scope.user.user_id,
           change_summary: "Added pinned library widget"
         ) do
      {:ok, saved} ->
        {:ok,
         %{
           receipt("add_to_draft", command["item_id"], command["version"])
           | dashboard_id: saved.dashboard_id,
             document_version: Document.version(saved),
             placement_id: placement.placement_id
         }}

      error ->
        normalize(error)
    end
  end

  defp observed(document, version),
    do: if(Document.version(document) == version, do: :ok, else: {:error, :conflict})

  defp receipt(event, item, version),
    do: %{
      version: 1,
      event: event,
      item_id: item,
      library_version: version,
      dashboard_id: nil,
      document_version: nil,
      placement_id: nil
    }

  defp normalize({:error, %Ecto.Changeset{}}), do: {:error, :invalid_input}
  defp normalize({:error, :library_version_conflict}), do: {:error, :conflict}
  defp normalize({:error, {:dashboard_version_conflict, _}}), do: {:error, :conflict}
  defp normalize({:error, {:invalid_library_widget, _}}), do: {:error, :invalid_widget}
  defp normalize({:error, {:invalid_dashboard_document, _}}), do: {:error, :invalid_widget}

  defp normalize({:error, code})
       when code in [:forbidden, :invalid_input, :invalid_widget, :conflict, :capacity],
       do: {:error, code}

  defp normalize({:error, code})
       when code in [
              :dashboard_not_found,
              :dashboard_archived,
              :dashboard_library_item_not_found,
              :dashboard_library_version_not_found
            ],
       do: {:error, :unavailable}

  defp normalize(_), do: {:error, :unknown}
end
