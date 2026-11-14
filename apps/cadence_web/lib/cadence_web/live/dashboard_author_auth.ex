defmodule CadenceWeb.DashboardAuthorAuth do
  @moduledoc """
  Who may author a mission's dashboards. The initial dashboard-author capability is an active human
  mission operator, expressed as a policy action so the grant can become narrower without moving
  its callers: the console's dashboard export (D19) and the ops shell.

  L8b: the legacy author-only pages (library, playlists, settings) went to the console, and with
  them this module's `on_mount` guard and its redirect to the console directory.
  """

  alias Cadence.Auth.{Policy, Scope}

  @doc false
  def authorized?(%Scope{} = scope, mission_id) when is_binary(mission_id) do
    Policy.authorize(scope, :author_dashboards, %{
      organization_id: scope.organization_id,
      mission_id: mission_id
    }) == :ok
  end

  def authorized?(_scope, _mission_id), do: false
end
