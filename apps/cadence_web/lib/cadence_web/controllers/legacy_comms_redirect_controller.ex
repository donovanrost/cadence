defmodule CadenceWeb.LegacyCommsRedirectController do
  @moduledoc """
  Issues 301 redirects from retired comms URL prefixes to their canonical paths.

  Bookmarks pinned to `/comms/links`, `/comms/path-templates`,
  `/comms/transport-profiles`, or `/comms/provider-profiles` resolve here so
  deep links still land on the right canonical page.
  """
  use CadenceWeb, :controller

  def link_templates_index(conn, %{"mission_id" => mission_id}) do
    redirect_301(conn, "/missions/#{mission_id}/comms/link-templates")
  end

  def link_templates_new(conn, %{"mission_id" => mission_id}) do
    redirect_301(conn, "/missions/#{mission_id}/comms/link-templates/new")
  end

  def shared_link_new(conn, %{"mission_id" => mission_id}) do
    redirect_301(conn, "/missions/#{mission_id}/comms/link-templates/new-shared-link")
  end

  def link_templates_show(conn, %{
        "mission_id" => mission_id,
        "path_template_id" => path_template_id
      }) do
    redirect_301(conn, "/missions/#{mission_id}/comms/link-templates/#{path_template_id}")
  end

  def link_templates_new_version(conn, %{
        "mission_id" => mission_id,
        "path_template_id" => path_template_id
      }) do
    redirect_301(
      conn,
      "/missions/#{mission_id}/comms/link-templates/#{path_template_id}/new-version"
    )
  end

  def protocol_behaviors_index(conn, %{"mission_id" => mission_id}) do
    redirect_301(conn, "/missions/#{mission_id}/comms/protocol-behaviors")
  end

  def protocol_behaviors_new(conn, %{"mission_id" => mission_id}) do
    redirect_301(conn, "/missions/#{mission_id}/comms/protocol-behaviors/new")
  end

  def protocol_behaviors_show(conn, %{
        "mission_id" => mission_id,
        "transport_profile_id" => transport_profile_id
      }) do
    redirect_301(
      conn,
      "/missions/#{mission_id}/comms/protocol-behaviors/#{transport_profile_id}"
    )
  end

  def protocol_behaviors_new_version(conn, %{
        "mission_id" => mission_id,
        "transport_profile_id" => transport_profile_id
      }) do
    redirect_301(
      conn,
      "/missions/#{mission_id}/comms/protocol-behaviors/#{transport_profile_id}/new-version"
    )
  end

  def providers_index(conn, %{"mission_id" => mission_id}) do
    redirect_301(conn, "/missions/#{mission_id}/comms/providers")
  end

  def providers_new(conn, %{"mission_id" => mission_id}) do
    redirect_301(conn, "/missions/#{mission_id}/comms/providers/new")
  end

  def providers_show(conn, %{
        "mission_id" => mission_id,
        "provider_profile_id" => provider_profile_id
      }) do
    redirect_301(conn, "/missions/#{mission_id}/comms/providers/#{provider_profile_id}")
  end

  def providers_new_version(conn, %{
        "mission_id" => mission_id,
        "provider_profile_id" => provider_profile_id
      }) do
    redirect_301(
      conn,
      "/missions/#{mission_id}/comms/providers/#{provider_profile_id}/new-version"
    )
  end

  def runtime_identities_index(conn, %{"mission_id" => mission_id}) do
    redirect_301(conn, "/missions/#{mission_id}/comms/runtime-identities")
  end

  def runtime_identities_new(conn, %{"mission_id" => mission_id}) do
    redirect_301(conn, "/missions/#{mission_id}/comms/runtime-identities/new")
  end

  defp redirect_301(conn, path) do
    conn
    |> put_status(:moved_permanently)
    |> redirect(to: path)
  end
end
