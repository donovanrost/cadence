defmodule CadenceWeb.Console.OrganizationController do
  @moduledoc """
  Organization-level reads under `/api/console/v1/organizations/:organization_id`
  (the `console_organization` pipeline authorizes membership). Contract:
  docs/apogee/api/setup.md.
  """

  use CadenceWeb, :controller

  alias Cadence.Reads.OrganizationMissions
  alias CadenceWeb.Console.ConfigJSON

  def missions(conn, _params) do
    missions = OrganizationMissions.list(conn.assigns.current_scope.organization_id)
    json(conn, %{data: ConfigJSON.encode(%{missions: missions})})
  end
end
