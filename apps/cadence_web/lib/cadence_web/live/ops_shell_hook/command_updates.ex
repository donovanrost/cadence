defmodule CadenceWeb.OpsShellHook.CommandUpdates do
  @moduledoc false

  alias Cadence.Platform.ScopedReadUpdates, as: ReadUpdates
  alias Cadence.Reads.OperationalContext
  alias Phoenix.Component

  def subscribe(socket) do
    scope =
      {socket.assigns.current_scope.organization_id, socket.assigns.current_mission.mission_id}

    if Phoenix.LiveView.connected?(socket) &&
         !match?(%{scope: ^scope}, socket.assigns[:ops_command_context_updates]) do
      socket = stop(socket)
      {org, mission} = scope
      :ok = ReadUpdates.subscribe(:commanding_changed, org, mission)

      Component.assign(socket, :ops_command_context_updates, %{
        scope: scope,
        token: make_ref(),
        pending: nil
      })
    else
      socket
    end
  end

  def stop(socket) do
    case socket.assigns[:ops_command_context_updates] do
      %{scope: {org, mission}, pending: pending} ->
        :ok = ReadUpdates.unsubscribe(:commanding_changed, org, mission)
        if pending, do: Process.cancel_timer(pending)

      _ ->
        :ok
    end

    Component.assign(socket, :ops_command_context_updates, nil)
  end

  def changed(socket, org, mission) do
    case socket.assigns do
      %{
        ops_context_active?: true,
        ops_command_context_updates: %{scope: {^org, ^mission}, pending: nil} = updates
      } ->
        pending = Process.send_after(self(), {:ops_command_context_flush, updates.token}, 250)
        Component.assign(socket, :ops_command_context_updates, %{updates | pending: pending})

      _ ->
        socket
    end
  end

  def flush(socket, token) do
    case socket.assigns do
      %{
        ops_context_active?: true,
        current_scope: %{organization_id: org},
        current_mission: %{mission_id: mission},
        ops_command_context_updates:
          %{scope: {org, mission}, token: ^token, pending: pending} = updates
      }
      when not is_nil(pending) ->
        socket
        |> Component.assign(:ops_command_context_updates, %{updates | pending: nil})
        |> refresh(org, mission)

      _ ->
        socket
    end
  end

  defp refresh(socket, org, mission) do
    deps = socket.assigns.ops_context_deps
    summary = deps.command_summary.(org, mission, [])
    context = socket.assigns.ops_context
    pinned = get_in(context, [:pinned_focus, :id])

    context =
      context
      |> OperationalContext.put_command_summary(summary, deps.observed_at.())
      |> OperationalContext.pin_command_focus(pinned)

    Component.assign(socket, :ops_context, context)
  end
end
