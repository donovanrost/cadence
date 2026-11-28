defmodule CadenceWeb.Console.ChannelAccess do
  @moduledoc """
  What keeps a console channel honest after its join (#1153). A join authorizes once; this makes
  the channel stop streaming when the person's access ends:

  - `watch/1` (called by a channel when its join succeeds) subscribes it to the person's access
    changes (`Cadence.Accounts.AccessEvents`: membership removed, role changed, account
    deactivated) and, for a platform admin in admin mode, schedules a re-check for when admin mode
    lapses.
  - `handle_changed/2` answers those messages (and a `command_group` push): it re-authorizes the
    mission with fresh credentials (`Access.fresh/1`, so an expired admin mode no longer counts)
    and closes the channel with `{:shutdown, :access_revoked}` if the person can no longer
    operate it. The client sees the channel close, and its rejoin goes through the join check.
  """

  alias Cadence.Accounts.AccessEvents
  alias CadenceWeb.Console.Access

  @spec watch(Phoenix.Socket.t()) :: Phoenix.Socket.t()
  def watch(socket) do
    :ok = AccessEvents.subscribe(socket.assigns.user_id)
    schedule_admin_mode_expiry(socket.assigns.console_credentials)
    socket
  end

  @doc "`:ok` while the person can still operate the mission, else `{:error, :access_revoked}`."
  @spec check(Phoenix.Socket.t()) :: :ok | {:error, :access_revoked}
  def check(socket) do
    case Access.authorize_mission(socket.assigns.console_credentials, socket.assigns.mission_id) do
      {:ok, _scope, _mission} -> :ok
      _revoked -> {:error, :access_revoked}
    end
  end

  @doc "The `handle_info` answer for an access message: keep the channel, or close it."
  @spec handle_changed(Phoenix.Socket.t(), term()) ::
          {:noreply, Phoenix.Socket.t()} | {:stop, term(), Phoenix.Socket.t()}
  def handle_changed(socket, _message) do
    case check(socket) do
      :ok -> {:noreply, socket}
      {:error, :access_revoked} -> {:stop, {:shutdown, :access_revoked}, socket}
    end
  end

  defp schedule_admin_mode_expiry(%{admin_mode?: true, admin_mode_expires_at: expires_at})
       when is_integer(expires_at) do
    delay_ms = max(expires_at - System.system_time(:second), 0) * 1_000 + 1_000
    Process.send_after(self(), :admin_mode_expired, delay_ms)
  end

  defp schedule_admin_mode_expiry(_credentials), do: :ok
end
