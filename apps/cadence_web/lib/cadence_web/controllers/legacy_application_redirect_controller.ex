defmodule CadenceWeb.LegacyApplicationRedirectController do
  @moduledoc """
  Redirects retired application-specific URLs to the generic application host.

  Legacy mappings are compatibility policy, not application-host dispatch.
  Keeping them here prevents the generic host from acquiring one `live_action`
  branch for every historical application URL.
  """

  use CadenceWeb, :controller

  alias CadenceWeb.ApplicationHostController

  def comms_overview(conn, %{"mission_id" => _mission_id} = params) do
    conn
    |> put_view(html: CadenceWeb.ApplicationHostHTML)
    |> ApplicationHostController.federated(Map.put(params, "application_key", "comms_overview"))
  end

  def telemetry_decom(conn, %{
        "mission_id" => mission_id,
        "spacecraft_id" => spacecraft_id
      }) do
    redirect_301(
      conn,
      ~p"/missions/#{mission_id}/spacecraft/#{spacecraft_id}/applications/telemetry_decom"
    )
  end

  defp redirect_301(conn, path) do
    conn
    |> put_status(:moved_permanently)
    |> redirect(to: path)
  end
end
