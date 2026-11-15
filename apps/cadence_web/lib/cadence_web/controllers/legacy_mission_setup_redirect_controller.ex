defmodule CadenceWeb.LegacyMissionSetupRedirectController do
  @moduledoc """
  §11c (B): legacy mission setup pages that moved to the console (DECISIONS #79), one hop each:

  - B1 `/missions/:id` → `/console/<org>/<mission>` (mission.home → Now)

  Slugs come from the signed-in organization (`CadenceWeb.ConsolePaths`), falling back to
  `/console`.
  """

  use CadenceWeb, :controller

  alias CadenceWeb.ConsolePaths

  def home(conn, params), do: go(conn, params, "")

  defp go(conn, %{"mission_id" => mission_id}, rest) do
    org = conn.assigns.current_scope && conn.assigns.current_scope.organization_id
    redirect(conn, to: ConsolePaths.mission(org, mission_id, rest))
  end
end
