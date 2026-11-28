defmodule CadenceWeb.Console.CommandGroupChannel do
  @moduledoc """
  `command_group:<mission_id>:<command_group_id>`: live progress for one
  command group (Uplink & verify). On join it pushes the full group view
  (`group`, `seq: 1`); after any commanding change in the mission it
  recomputes, at most once a second, and pushes the view again only when it
  changed. The view is the `GET /command-groups/:id` payload.
  Contract: docs/apogee/api/realtime.md.
  """

  use Phoenix.Channel

  alias Cadence.Platform.ScopedReadUpdates
  alias Cadence.Reads.CommandGroups
  alias CadenceWeb.Console.{Access, ChannelAccess, CommandGroupJSON}

  @refresh_ms 1_000

  @impl true
  def join("command_group:" <> rest, _payload, socket) do
    with [mission_id, group_id] <- String.split(rest, ":", parts: 2),
         {:ok, scope, mission} <-
           Access.authorize_mission(socket.assigns.console_credentials, mission_id),
         {:ok, _view} <-
           CommandGroups.get(scope.organization_id, mission.mission_id, group_id, viewer(scope)) do
      :ok =
        ScopedReadUpdates.subscribe(
          :commanding_changed,
          scope.organization_id,
          mission.mission_id
        )

      send(self(), :push)

      {:ok, %{command_group_id: group_id},
       assign(socket,
         scope: scope,
         mission_id: mission.mission_id,
         group_id: group_id,
         seq: 0,
         digest: nil,
         timer: nil
       )
       |> ChannelAccess.watch()}
    else
      {:error, :command_group_not_found} -> {:error, %{reason: "command_group_not_found"}}
      {:error, reason} when is_atom(reason) -> {:error, %{reason: Atom.to_string(reason)}}
      _other -> {:error, %{reason: "command_group_not_found"}}
    end
  end

  @impl true
  # The person's access changed (#1153): re-check, and close if it no longer passes.
  def handle_info({:access_changed, _user_id} = message, socket),
    do: ChannelAccess.handle_changed(socket, message)

  def handle_info(:admin_mode_expired, socket),
    do: ChannelAccess.handle_changed(socket, :admin_mode_expired)

  def handle_info({:commanding_changed, _org, _mission}, %{assigns: %{timer: nil}} = socket),
    do: {:noreply, assign(socket, :timer, Process.send_after(self(), :push, @refresh_ms))}

  def handle_info({:commanding_changed, _org, _mission}, socket), do: {:noreply, socket}

  # Every push re-checks that the person can still operate the mission (#1153): this channel
  # carries a group's live commanding state.
  def handle_info(:push, socket) do
    case ChannelAccess.check(socket) do
      :ok -> push_view(socket)
      {:error, :access_revoked} -> {:stop, {:shutdown, :access_revoked}, socket}
    end
  end

  def handle_info(_other, socket), do: {:noreply, socket}

  defp push_view(socket) do
    %{scope: scope, mission_id: mission, group_id: id} = socket.assigns

    case CommandGroups.get(scope.organization_id, mission, id, viewer(scope)) do
      {:ok, view} ->
        {:noreply, maybe_push(assign(socket, :timer, nil), CommandGroupJSON.push(view))}

      {:error, _reason} ->
        {:noreply, assign(socket, :timer, nil)}
    end
  end

  defp maybe_push(socket, payload) do
    digest = :erlang.phash2(payload)

    if digest == socket.assigns.digest do
      socket
    else
      seq = socket.assigns.seq + 1
      push(socket, "group", %{seq: seq, group: payload})
      assign(socket, seq: seq, digest: digest)
    end
  end

  defp viewer(scope), do: scope.user && scope.user.user_id
end
