defmodule CadenceWeb.SettingsPage do
  @moduledoc """
  Scoped settings live updates for host pages that embed settings sections.

  §11c B2: the mission settings pages redirect to the console (`/setup/settings`), so the host no
  longer serves a settings page or its writes; the pages below (batch C's) still embed sections.
  """
  import Phoenix.Component, only: [assign: 3]
  alias Cadence.Platform.ScopedReadUpdates

  @consumers [
    "/missions/:mission_id/spacecraft/:spacecraft_id",
    "/missions/:mission_id/ops/commands/workspace"
  ]

  def prepare(socket, info, _path), do: subscribe(socket, info)

  def relevant?(socket, org, mission) do
    case socket.assigns[:settings_subscription] do
      {^org, current} -> is_nil(mission) or mission == current
      _ -> false
    end
  end

  defp subscribe(socket, info) do
    identity =
      if info.route in @consumers,
        do: {socket.assigns.current_scope.organization_id, info.params["mission_id"]},
        else: nil

    previous = socket.assigns[:settings_subscription]

    if identity != previous do
      Enum.each(topics(previous), fn {org, mission} ->
        ScopedReadUpdates.unsubscribe(:settings_changed, org, mission)
      end)

      subscribe_topics(socket, identity)
    end

    assign(socket, :settings_subscription, identity)
  end

  defp subscribe_topics(socket, identity) do
    if Phoenix.LiveView.connected?(socket) do
      Enum.each(topics(identity), fn {org, mission} ->
        ScopedReadUpdates.subscribe(:settings_changed, org, mission)
      end)
    end
  end

  defp topics(nil), do: []
  defp topics({org, mission}), do: Enum.uniq([{org, nil}, {org, mission}])
end
