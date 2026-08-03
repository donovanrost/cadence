defmodule CadenceWeb.DashboardExportController do
  @moduledoc false

  use CadenceWeb, :controller

  alias Cadence.Dashboards.{Document, Management}
  alias Cadence.Missions

  def show(conn, %{"mission_id" => mission_id, "dashboard_id" => dashboard_id}) do
    scope = conn.assigns.current_scope

    with true <- CadenceWeb.DashboardAuthorAuth.authorized?(scope, mission_id),
         {:ok, _mission} <- Missions.fetch_mission(scope.organization_id, mission_id),
         {:ok, %Document{} = document} <-
           Cadence.Dashboards.fetch_document_for_mode(
             scope.organization_id,
             mission_id,
             dashboard_id,
             :edit
           ),
         {:ok, artifact} <-
           Cadence.Dashboards.export_bundle(document,
             exported_by: current_user_id(scope)
           ),
         {:ok, _deployment} <-
           Management.record_deployment(
             scope.organization_id,
             mission_id,
             document,
             artifact,
             "portable_json",
             created_by: current_user_id(scope)
           ) do
      conn
      |> put_resp_content_type("application/json")
      |> put_resp_header(
        "content-disposition",
        ~s(attachment; filename="#{safe_filename(document.name)}.cadence-dashboard.json")
      )
      |> send_resp(200, artifact)
    else
      false -> conn |> put_status(:forbidden) |> text("Forbidden")
      {:error, _reason} -> conn |> put_status(:not_found) |> text("Not found")
    end
  end

  defp safe_filename(name) do
    name
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
    |> case do
      "" -> "dashboard"
      value -> value
    end
  end

  defp current_user_id(%{user: %{user_id: user_id}}) when is_binary(user_id), do: user_id
  defp current_user_id(_scope), do: nil
end
