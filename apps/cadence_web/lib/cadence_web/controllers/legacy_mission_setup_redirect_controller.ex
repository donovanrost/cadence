defmodule CadenceWeb.LegacyMissionSetupRedirectController do
  @moduledoc """
  §11c (B): legacy mission setup pages that moved to the console (DECISIONS #79), one hop each:

  - B1 `/missions/:id` → `/console/<org>/<mission>` (mission.home → Now)
  - B2 `/missions/:id/settings[/:section_id]` → `…/setup/settings[/:section_id]`
  - B3 `/missions/:id/spacecraft[/new]` → `…/setup/spacecraft[/new]`
  - B4 `/missions/:id/spacecraft/profiles[/new | /:profile_id]` → `…/setup/profiles[/new | /:profile_id]`
  - B6 `/missions/:id/catalog` → `…/setup/catalog`; `…/catalog/new` → `…/setup/catalog/import`;
      `…/catalog/databases/:id` → `…/setup/catalog/:id`; `…/catalog/imports/:id` → `…/setup/catalog/import/:id`
      (artifacts stay, L18)
  - B7 `/missions/:id/comms` → `…/setup/comms`; `…/comms/transports[/new]` → `…/setup/comms/transports`;
      `…/comms/transports/:id` → `…/setup/comms/transports/:id`
  - B8 `/missions/:id/comms/ground-stations[/new]` → `…/setup/stations`;
      `…/comms/ground-stations/:id[/edit]` → `…/setup/stations/:id`
  - B11 `/missions/:id/applications` → `…/setup/apps`
  - B5 `/missions/:id/spacecraft/:sid/readiness | /routing | /commanding` → `…/setup/spacecraft/:sid`
      (one page; the bare show, `/identity` and `/edit` stay, L17/L22)

  Slugs come from the signed-in organization (`CadenceWeb.ConsolePaths`), falling back to
  `/console`.
  """

  use CadenceWeb, :controller

  alias CadenceWeb.ConsolePaths

  def home(conn, params), do: go(conn, params, "")

  def settings(conn, %{"section_id" => id} = params),
    do: go(conn, params, "/setup/settings/" <> ConsolePaths.segment(id))

  def settings(conn, params), do: go(conn, params, "/setup/settings")

  def spacecraft(conn, params), do: go(conn, params, "/setup/spacecraft")
  def new_spacecraft(conn, params), do: go(conn, params, "/setup/spacecraft/new")

  def profiles(conn, params), do: go(conn, params, "/setup/profiles")
  def new_profile(conn, params), do: go(conn, params, "/setup/profiles/new")

  def profile(conn, %{"profile_id" => id} = params),
    do: go(conn, params, "/setup/profiles/" <> ConsolePaths.segment(id))

  def catalog(conn, params), do: go(conn, params, "/setup/catalog")

  def catalog_import(conn, %{"import_run_id" => id} = params),
    do: go(conn, params, "/setup/catalog/import/" <> ConsolePaths.segment(id))

  def catalog_import(conn, params), do: go(conn, params, "/setup/catalog/import")

  def catalog_database(conn, %{"catalog_database_id" => id} = params),
    do: go(conn, params, "/setup/catalog/" <> ConsolePaths.segment(id))

  def comms(conn, params), do: go(conn, params, "/setup/comms")
  def transports(conn, params), do: go(conn, params, "/setup/comms/transports")

  def transport(conn, %{"transport_id" => id} = params),
    do: go(conn, params, "/setup/comms/transports/" <> ConsolePaths.segment(id))

  def stations(conn, params), do: go(conn, params, "/setup/stations")

  def station(conn, %{"ground_station_id" => id} = params),
    do: go(conn, params, "/setup/stations/" <> ConsolePaths.segment(id))

  def applications(conn, params), do: go(conn, params, "/setup/apps")

  def spacecraft_page(conn, %{"spacecraft_id" => id} = params),
    do: go(conn, params, "/setup/spacecraft/" <> ConsolePaths.segment(id))

  defp go(conn, %{"mission_id" => mission_id}, rest) do
    org = conn.assigns.current_scope && conn.assigns.current_scope.organization_id
    redirect(conn, to: ConsolePaths.mission(org, mission_id, rest))
  end
end
