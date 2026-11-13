defmodule CadenceWeb.DashboardAuthorAuth do
  @moduledoc """
  Router-level authorization boundary for mission-shared dashboard mutations.

  The initial dashboard-author capability is an active human mission operator.
  It is intentionally expressed as a policy action so the grant can become
  narrower without moving or rewriting authoring routes.
  """

  import Phoenix.LiveView, only: [put_flash: 3, redirect: 2]

  alias Cadence.{Missions, Organizations}
  alias Cadence.Auth.{Policy, Scope}

  def on_mount(:require_dashboard_author, %{"mission_id" => mission_id}, _session, socket) do
    case socket.assigns[:current_scope] do
      %Scope{} = scope -> authorize(scope, mission_id, socket)
      _missing_scope -> {:halt, redirect(socket, to: "/sign-in")}
    end
  end

  @doc false
  def authorized?(%Scope{} = scope, mission_id) when is_binary(mission_id) do
    Policy.authorize(scope, :author_dashboards, %{
      organization_id: scope.organization_id,
      mission_id: mission_id
    }) == :ok
  end

  def authorized?(_scope, _mission_id), do: false

  defp authorize(scope, mission_id, socket) do
    if authorized?(scope, mission_id) do
      {:cont, socket}
    else
      {:halt,
       socket
       |> put_flash(:error, "You do not have permission to author mission dashboards.")
       |> redirect(to: console_directory(scope.organization_id, mission_id))}
    end
  end

  @doc """
  The console's dashboards directory for a mission (L8a: the legacy directory is gone), by the
  organization's and mission's slugs; `/console` when either can't be found.
  """
  def console_directory(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    with {:ok, mission} <- Missions.fetch_mission(organization_id, mission_id),
         {:ok, organization} <- Organizations.fetch_organization(organization_id) do
      "/console/#{segment(organization.slug)}/#{segment(mission.slug)}/telemetry/dashboards"
    else
      _other -> "/console"
    end
  end

  def console_directory(_organization_id, _mission_id), do: "/console"

  defp segment(value), do: URI.encode(value, &URI.char_unreserved?/1)
end
