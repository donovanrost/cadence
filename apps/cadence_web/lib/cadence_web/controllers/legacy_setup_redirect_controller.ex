defmodule CadenceWeb.LegacySetupRedirectController do
  @moduledoc """
  Legacy mission Ops pages that moved to the console's Setup (DECISIONS #79), one hop each:

  - L1 `/missions/:id/ops/requirements[/new]` → `…/setup/contact-planning`;
    `/missions/:id/ops/requirements/:requirement_id` → `…/setup/contact-planning/requirements/:id`
  - L2 `/missions/:id/ops/requirement-templates` → `…/setup/contact-planning`
  - L3 `/missions/:id/ops/planning/policy` → `…/setup/contact-planning/policy`
  - L11 `/missions/:id/ops/data-sources[/registration/new]` → `…/setup/data-sources`;
    `/missions/:id/ops/data-sources/:data_source_id[/…]` → `…/setup/data-sources/:id`
  - L12 `/missions/:id/comms/providers[/new]` → `…/setup/stations/providers`;
    `/missions/:id/comms/providers/:provider_id` → `…/setup/stations/providers/:provider_id`

  Slugs come from the signed-in organization (`CadenceWeb.ConsolePaths`), falling back to
  `/console`.
  """

  use CadenceWeb, :controller

  alias CadenceWeb.ConsolePaths

  def requirements(conn, params), do: go(conn, params, "/setup/contact-planning")

  def requirement(conn, %{"contact_requirement_id" => id} = params),
    do: go(conn, params, "/setup/contact-planning/requirements/" <> ConsolePaths.segment(id))

  def templates(conn, params), do: go(conn, params, "/setup/contact-planning")
  def policy(conn, params), do: go(conn, params, "/setup/contact-planning/policy")
  def data_sources(conn, params), do: go(conn, params, "/setup/data-sources")

  def providers(conn, params), do: go(conn, params, "/setup/stations/providers")

  def provider(conn, %{"provider_id" => id} = params),
    do: go(conn, params, "/setup/stations/providers/" <> ConsolePaths.segment(id))

  def data_source(conn, %{"data_source_id" => id} = params),
    do: go(conn, params, "/setup/data-sources/" <> ConsolePaths.segment(id))

  defp go(conn, %{"mission_id" => mission_id}, rest) do
    org = conn.assigns.current_scope && conn.assigns.current_scope.organization_id
    redirect(conn, to: ConsolePaths.mission(org, mission_id, rest))
  end
end
