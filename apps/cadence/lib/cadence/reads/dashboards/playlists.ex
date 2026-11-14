defmodule Cadence.Reads.Dashboards.Playlists do
  @moduledoc """
  Scoped playlist directory. L8b: the legacy present page and its search went to the console
  (D23/D24), and with them `present/5` and `search/3`.
  """
  alias Cadence.Dashboards.{Authoring, PlaylistInput, PlaylistStore}

  def directory(scope, mission, params) do
    with :ok <- Authoring.authorize(scope, mission),
         {:ok, query} <- PlaylistInput.query(params) do
      {:ok,
       Map.merge(identity(scope, mission), %{
         query: query,
         playlists: PlaylistStore.list(scope.organization_id, mission, query),
         choices: PlaylistStore.choices(scope.organization_id, mission, %{q: "", after: nil})
       })}
    else
      _ -> {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  defp identity(scope, mission),
    do: %{version: 1, organization_id: scope.organization_id, mission_id: mission}
end
