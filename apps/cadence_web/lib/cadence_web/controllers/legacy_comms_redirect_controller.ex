defmodule CadenceWeb.LegacyCommsRedirectController do
  @moduledoc """
  Issues 301 redirects from retired comms URL prefixes to the comms overview.

  Bookmarks pinned to `/comms/links`, `/comms/path-templates`,
  `/comms/transport-profiles`, `/comms/provider-profiles`, or
  `/comms/source-endpoints` resolve here so deep links still land on a
  useful page. The pages those URLs previously served (link templates,
  protocol behaviors, providers, runtime identities) have been retired as
  primary setup surfaces in favor of Spacecraft Profiles, Transports, and
  Routing Rules.
  """
  use CadenceWeb, :controller

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

  def providers_index(conn, %{"mission_id" => mission_id}) do
    redirect_301(conn, "/missions/#{mission_id}/comms/transports")
  end

  def providers_new(conn, %{"mission_id" => mission_id}) do
    redirect_301(conn, "/missions/#{mission_id}/comms/transports/new")
  end

  def providers_show(conn, %{
        "mission_id" => mission_id
      }) do
    redirect_301(conn, "/missions/#{mission_id}/comms/transports")
  end

  def providers_new_version(conn, %{
        "mission_id" => mission_id
      }) do
    redirect_301(conn, "/missions/#{mission_id}/comms/transports")
  end

  def runtime_identities_index(conn, %{"mission_id" => mission_id}),
    do: overview(conn, mission_id)

  def runtime_identities_new(conn, %{"mission_id" => mission_id}),
    do: overview(conn, mission_id)

  defp overview(conn, mission_id) do
    redirect_301(conn, "/missions/#{mission_id}/comms")
  end

  defp redirect_301(conn, path) do
    conn
    |> put_status(:moved_permanently)
    |> redirect(to: path)
  end
end
