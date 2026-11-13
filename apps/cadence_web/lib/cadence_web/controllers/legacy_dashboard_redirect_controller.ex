defmodule CadenceWeb.LegacyDashboardRedirectController do
  @moduledoc """
  L8 cutover (owner: api-ops): the legacy dashboards directory, viewer and editor send the browser
  to the console in one hop, so bookmarks and shared links keep working.

  - `/missions/:id/ops/dashboards` → `/console/<org>/<mission>/telemetry/dashboards`
  - `/missions/:id/ops/dashboards/:dashboard_id` → `…/telemetry/dashboards/:dashboard_id`
  - `/missions/:id/ops/dashboards/:dashboard_id/edit` → the same with `?edit=1`

  Console URLs carry slugs, legacy ones ids: the slugs come from the signed-in organization's
  mission. A mission that isn't the organization's (or doesn't exist) falls back to `/console`.
  Query parameters the console reads are kept: the time range (`from`, `to`), the spacecraft
  (`spacecraft`, legacy `spacecraft_id`), `refresh` and `kiosk` for the viewer; the search and
  tag filters for the directory (`q`, `tags`; legacy `query`, `tag`). The pages the console
  doesn't have yet (library, playlists, settings, shares, snapshots, activity, diagnostics) stay
  on the legacy routes.
  """

  use CadenceWeb, :controller

  alias Cadence.{Missions, Organizations}

  @viewer_params ~w(from to spacecraft refresh kiosk)
  @directory_params ~w(q tags)

  def directory(conn, %{"mission_id" => mission_id} = params),
    do: go(conn, mission_id, "", directory_query(params))

  def viewer(conn, %{"mission_id" => mission_id, "dashboard_id" => dashboard_id} = params),
    do: go(conn, mission_id, "/" <> segment(dashboard_id), viewer_query(params))

  def edit(conn, %{"mission_id" => mission_id, "dashboard_id" => dashboard_id} = params),
    do:
      go(
        conn,
        mission_id,
        "/" <> segment(dashboard_id),
        Map.put(viewer_query(params), "edit", "1")
      )

  defp go(conn, mission_id, rest, query) do
    path =
      case slugs(conn.assigns.current_scope.organization_id, mission_id) do
        {:ok, org, mission} ->
          "/console/#{segment(org)}/#{segment(mission)}/telemetry/dashboards" <> rest <> qs(query)

        :error ->
          "/console"
      end

    redirect(conn, to: path)
  end

  defp slugs(organization_id, mission_id) when is_binary(organization_id) do
    with {:ok, mission} <- Missions.fetch_mission(organization_id, mission_id),
         {:ok, organization} <- Organizations.fetch_organization(organization_id) do
      {:ok, organization.slug, mission.slug}
    else
      _other -> :error
    end
  end

  defp slugs(_organization_id, _mission_id), do: :error

  defp directory_query(params) do
    params
    |> Map.put_new("q", params["query"])
    |> Map.put_new("tags", params["tag"])
    |> Map.take(@directory_params)
  end

  defp viewer_query(params) do
    params
    |> Map.put_new("spacecraft", params["spacecraft_id"])
    |> Map.take(@viewer_params)
  end

  defp qs(query) do
    case Map.reject(query, fn {_key, value} -> not is_binary(value) or value == "" end) do
      empty when map_size(empty) == 0 -> ""
      kept -> "?" <> URI.encode_query(Enum.sort(kept))
    end
  end

  defp segment(value), do: URI.encode(value, &URI.char_unreserved?/1)
end
