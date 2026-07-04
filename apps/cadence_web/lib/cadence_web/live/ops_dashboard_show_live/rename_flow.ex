defmodule CadenceWeb.OpsDashboardShowLive.RenameFlow do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]

  alias Cadence.Dashboards.Document

  @change_summary "Renamed dashboard"

  def rename(socket, params, opts \\ []) when is_map(params) do
    %{current_scope: scope, current_mission: mission, dashboard_document: current_document} =
      socket.assigns

    document = renamed_document(current_document, params)

    case persist_document(opts).(socket, document, change_summary: @change_summary) do
      {:ok, socket} ->
        {:ok,
         socket
         |> assign(:ops_dashboards, list_dashboard_summaries(opts).(scope, mission))
         |> assign(:panel, nil)}

      {:error, socket} ->
        {:error, socket}
    end
  end

  def renamed_document(%Document{} = document, params) when is_map(params) do
    attrs = %{
      name: normalize_text(params["name"]) || document.name,
      description: normalize_text(params["description"])
    }

    %{document | name: attrs.name, description: attrs.description}
  end

  defp normalize_text(value), do: CadenceWeb.CommsComponents.normalize_text(value)

  defp persist_document(opts) do
    Keyword.fetch!(opts, :persist_document)
  end

  defp list_dashboard_summaries(opts) do
    Keyword.get(opts, :list_dashboard_summaries, fn scope, mission ->
      Cadence.Dashboards.list_dashboard_summaries(scope.organization_id, mission.mission_id)
    end)
  end
end
