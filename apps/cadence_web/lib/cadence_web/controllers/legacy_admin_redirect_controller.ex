defmodule CadenceWeb.LegacyAdminRedirectController do
  @moduledoc """
  Legacy organization and platform pages that moved to the console (DECISIONS #79), one hop each:

  - L4 `/missions` → `/console/<org>/org/missions`; `/missions/new` → `…/org/missions/new`
  - L7 `/admin` → `/console/admin`; `/admin/runtime` → `/console/admin/runtime`;
    `/admin/organizations[/new]` → `/console/admin/organizations`;
    `/admin/organizations/:org_id[/invite]` → `/console/admin/organizations/:org_id` (the console
    takes the organization id, and inviting happens from that page)
  """

  use CadenceWeb, :controller

  alias CadenceWeb.ConsolePaths

  def missions(conn, _params), do: org(conn, "/org/missions")
  def new_mission(conn, _params), do: org(conn, "/org/missions/new")

  def admin(conn, _params), do: redirect(conn, to: "/console/admin")
  def runtime(conn, _params), do: redirect(conn, to: "/console/admin/runtime")
  def organizations(conn, _params), do: redirect(conn, to: "/console/admin/organizations")

  def organization(conn, %{"org_id" => id}),
    do: redirect(conn, to: "/console/admin/organizations/" <> ConsolePaths.segment(id))

  defp org(conn, rest) do
    org = conn.assigns.current_scope && conn.assigns.current_scope.organization_id
    redirect(conn, to: ConsolePaths.organization(org, rest))
  end
end
