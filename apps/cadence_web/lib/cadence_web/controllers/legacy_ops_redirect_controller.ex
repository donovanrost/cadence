defmodule CadenceWeb.LegacyOpsRedirectController do
  @moduledoc """
  Preserves authenticated Ops bookmarks while canonical routes move.
  """

  use CadenceWeb, :controller

  def telemetry_explore(conn, %{"mission_id" => mission_id}) do
    destination =
      with_query(
        "/missions/#{mission_id}/ops/explore",
        conn.query_string
      )

    conn
    |> put_status(:moved_permanently)
    |> redirect(to: destination)
  end

  defp with_query(path, ""), do: path
  defp with_query(path, query_string), do: path <> "?" <> query_string
end
