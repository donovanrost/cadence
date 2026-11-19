defmodule CadenceWeb.LegacyAdminRedirectController do
  @moduledoc """
  Legacy organization and platform pages that moved to the console (DECISIONS #79), one hop each:

  - §11c A1 `/` → `/console/<org>` (signed out → `/sign-in`; a platform admin with no organization
    selected → `/console/admin`, as the old root did; otherwise no organization → `/console`)
  - §11c A2 `/settings[/:section_id]` → `/console/<org>/org/settings[/:section_id]`
  - L4 `/missions` → `/console/<org>/org/missions`; `/missions/new` → `…/org/missions/new`
  - L7 `/admin` → `/console/admin`; `/admin/runtime` → `/console/admin/runtime`;
    `/admin/organizations[/new]` → `/console/admin/organizations`;
    `/admin/organizations/:org_id[/invite]` → `/console/admin/organizations/:org_id` (the console
    takes the organization id, and inviting happens from that page)
  - L13 `/provider-accounts[/new]` → `/console/<org>/org/provider-accounts`;
    `/provider-accounts/:provider_account_id` → `…/org/provider-accounts/:id`
  """

  use CadenceWeb, :controller

  alias Cadence.Auth.Scope
  alias CadenceWeb.ConsolePaths

  def home(conn, _params) do
    scope = conn.assigns.current_scope

    if scope && is_nil(scope.organization_id) && Scope.platform_admin_eligible?(scope),
      do: redirect(conn, to: "/console/admin"),
      else: org(conn, "")
  end

  def settings(conn, %{"section_id" => id}),
    do: org(conn, "/org/settings/" <> ConsolePaths.segment(id))

  def settings(conn, _params), do: org(conn, "/org/settings")

  def missions(conn, _params), do: org(conn, "/org/missions")
  def new_mission(conn, _params), do: org(conn, "/org/missions/new")

  def provider_accounts(conn, _params), do: org(conn, "/org/provider-accounts")

  def provider_account(conn, %{"provider_account_id" => id}),
    do: org(conn, "/org/provider-accounts/" <> ConsolePaths.segment(id))

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
