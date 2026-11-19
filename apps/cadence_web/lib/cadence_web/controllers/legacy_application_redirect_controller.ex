defmodule CadenceWeb.LegacyApplicationRedirectController do
  @moduledoc """
  Redirects retired application URLs to the console (DECISIONS #79): a spacecraft's telemetry
  decom pages go to the spacecraft's decom app in Setup.

  Legacy mappings are compatibility policy, not application-host dispatch.
  """

  use CadenceWeb, :controller

  alias CadenceWeb.ConsolePaths

  def telemetry_decom(conn, %{"mission_id" => mission_id, "spacecraft_id" => spacecraft_id}) do
    org = conn.assigns.current_scope && conn.assigns.current_scope.organization_id
    rest = "/setup/spacecraft/#{ConsolePaths.segment(spacecraft_id)}/apps/telemetry_decom"

    conn
    |> put_status(:moved_permanently)
    |> redirect(to: ConsolePaths.mission(org, mission_id, rest))
  end
end
