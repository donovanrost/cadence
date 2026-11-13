defmodule CadenceWeb.MissionPage do
  @moduledoc "Host composition for the mission overview page."

  alias Cadence.Reads.Missions.Pages

  @routes %{
    "/missions/:mission_id" => "mission_overview"
  }

  def load(scope, %{route: route, params: params}) do
    case Map.fetch(@routes, route) do
      {:ok, page} -> snapshot(scope, page, params["mission_id"])
      :error -> nil
    end
  end

  def presentation(assigns), do: assigns[:mission_page]

  defp snapshot(scope, page, mission_id) do
    case Pages.load(scope, page, mission_id) do
      {:ok, data} -> %{version: 1, page: page, status: "ready", data: data}
      {:error, _reason} -> %{version: 1, page: page, status: "unavailable"}
    end
  rescue
    _exception -> %{version: 1, page: page, status: "unavailable"}
  end
end
