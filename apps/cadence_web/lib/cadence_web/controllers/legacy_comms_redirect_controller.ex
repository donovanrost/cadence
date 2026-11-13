defmodule CadenceWeb.LegacyCommsRedirectController do
  @moduledoc """
  Issues 301 redirects from retired comms URL prefixes to the comms overview.

  Bookmarks pinned to `/comms/links`, `/comms/path-templates`,
  `/comms/transport-profiles`, `/comms/provider-profiles`, or
  `/comms/source-endpoints` resolve here so deep links still land on a
  useful page in the console's Setup › Comms. The pages those URLs previously served (link templates,
  protocol behaviors, providers, runtime identities) have been retired as
  primary setup surfaces in favor of Spacecraft Profiles, Transports, and
  Routing Rules.
  """
  use CadenceWeb, :controller

  alias CadenceWeb.ConsolePaths

  def link_templates_index(conn, %{"mission_id" => mission_id}),
    do: overview(conn, mission_id)

  def link_templates_new(conn, %{"mission_id" => mission_id}),
    do: overview(conn, mission_id)

  def shared_link_new(conn, %{"mission_id" => mission_id}),
    do: overview(conn, mission_id)

  def link_templates_show(conn, %{"mission_id" => mission_id}),
    do: overview(conn, mission_id)

  def link_templates_new_version(conn, %{"mission_id" => mission_id}),
    do: overview(conn, mission_id)

  def protocol_behaviors_index(conn, %{"mission_id" => mission_id}),
    do: overview(conn, mission_id)

  def protocol_behaviors_new(conn, %{"mission_id" => mission_id}),
    do: overview(conn, mission_id)

  def protocol_behaviors_show(conn, %{"mission_id" => mission_id}),
    do: overview(conn, mission_id)

  def protocol_behaviors_new_version(conn, %{"mission_id" => mission_id}),
    do: overview(conn, mission_id)

  def providers_index(conn, %{"mission_id" => mission_id}), do: transports(conn, mission_id)
  def providers_new(conn, %{"mission_id" => mission_id}), do: transports(conn, mission_id)
  def providers_show(conn, %{"mission_id" => mission_id}), do: transports(conn, mission_id)
  def providers_new_version(conn, %{"mission_id" => mission_id}), do: transports(conn, mission_id)

  def runtime_identities_index(conn, %{"mission_id" => mission_id}),
    do: overview(conn, mission_id)

  def runtime_identities_new(conn, %{"mission_id" => mission_id}),
    do: overview(conn, mission_id)

  # The console's Setup › Comms (DECISIONS #79), slugs from the signed-in organization.
  defp overview(conn, mission_id), do: redirect_301(conn, mission_id, "/setup/comms")
  defp transports(conn, mission_id), do: redirect_301(conn, mission_id, "/setup/comms/transports")

  defp redirect_301(conn, mission_id, rest) do
    org = conn.assigns.current_scope && conn.assigns.current_scope.organization_id

    conn
    |> put_status(:moved_permanently)
    |> redirect(to: ConsolePaths.mission(org, mission_id, rest))
  end
end
