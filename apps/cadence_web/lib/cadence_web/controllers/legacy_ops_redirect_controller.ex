defmodule CadenceWeb.LegacyOpsRedirectController do
  @moduledoc """
  Preserves authenticated Ops bookmarks: `/missions/:id/ops/telemetry/explore` goes to the
  console's Telemetry (DECISIONS #79), keeping the time range (`from`, `to`) and the point
  (legacy `point_id`, the console's `p`).
  """

  use CadenceWeb, :controller

  alias CadenceWeb.ConsolePaths

  def telemetry_explore(conn, %{"mission_id" => mission_id} = params) do
    org = conn.assigns.current_scope && conn.assigns.current_scope.organization_id
    query = params |> Map.take(~w(from to)) |> Map.put("p", params["point_id"])

    conn
    |> put_status(:moved_permanently)
    |> redirect(to: ConsolePaths.mission(org, mission_id, "/telemetry", query))
  end
end
