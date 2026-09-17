defmodule CadenceWeb.OpsCommandWorkspacePage do
  @moduledoc "Captured Ops commanding workspace with independent reads and consumed writes."
  alias Cadence.Management.Commanding.RequestAuthoring
  alias CadenceWeb.OpsCommandWorkspaceSession, as: Session
  alias Phoenix.Component
  @route "/missions/:mission_id/ops/commands/workspace"
  @id "commanding.workspace"
  @events ~w(browse catalog_page create_stage preview_targets save_targets enqueue preview_batch submit cancel_item edit_details)

  def prepare(socket, %{route: @route, params: params}, path) do
    scope = socket.assigns.current_scope
    identity = {scope.organization_id, scope.user.user_id, params["mission_id"], path}

    session =
      case socket.assigns[:ops_command_workspace_session] do
        %{identity: ^identity} = previous -> previous
        _ -> Session.new(identity, params)
      end

    socket = start_updates(socket, session)
    {page, session} = snapshot(scope, session)
    Component.assign(socket, ops_command_workspace_session: session, ops_page: page)
  end

  def prepare(socket, _, _) do
    socket
    |> stop_updates()
    |> Component.assign(:ops_command_workspace_session, nil)
  end

  def changed(socket, org, mission) do
    case socket.assigns[:ops_command_workspace_updates] do
      %{scope: {^org, ^mission}, pending: nil, token: token} = updates ->
        timer = Process.send_after(self(), {:command_workspace_flush, token}, 250)
        Component.assign(socket, :ops_command_workspace_updates, %{updates | pending: timer})

      _ ->
        socket
    end
  end

  def flush(socket, token) do
    case socket.assigns[:ops_command_workspace_updates] do
      %{token: ^token} = updates ->
        socket
        |> Component.assign(:ops_command_workspace_updates, %{updates | pending: nil})
        |> invalidate(token)

      _ ->
        socket
    end
  end

  # Reconcile missed notices and changes to shared catalog/access data as well.
  def reconcile(socket, token) do
    case socket.assigns[:ops_command_workspace_updates] do
      %{token: ^token} = updates ->
        timer = Process.send_after(self(), {:command_workspace_reconcile, token}, 30_000)

        socket
        |> Component.assign(:ops_command_workspace_updates, %{updates | timer: timer})
        |> invalidate(token)

      _ ->
        socket
    end
  end

  defp invalidate(socket, token) do
    case socket.assigns[:ops_command_workspace_session] do
      %{token: ^token, identity: {_, _, _, path}} ->
        Phoenix.LiveView.push_event(socket, "cadence:ops-page-changed", %{
          id: @id,
          token: token,
          path: path
        })

      _ ->
        socket
    end
  end

  defp start_updates(socket, %{token: token, identity: {org, _, mission, _}}) do
    if Phoenix.LiveView.connected?(socket) &&
         !match?(%{token: ^token}, socket.assigns[:ops_command_workspace_updates]) do
      socket = stop_updates(socket)
      # The shared Ops frame owns the PubSub subscription across page changes.
      timer = Process.send_after(self(), {:command_workspace_reconcile, token}, 30_000)

      Component.assign(socket, :ops_command_workspace_updates, %{
        scope: {org, mission},
        token: token,
        timer: timer,
        pending: nil
      })
    else
      socket
    end
  end

  defp stop_updates(socket) do
    case socket.assigns[:ops_command_workspace_updates] do
      %{timer: timer, pending: pending} ->
        Process.cancel_timer(timer)
        if pending, do: Process.cancel_timer(pending)

      _ ->
        :ok
    end

    Component.assign(socket, :ops_command_workspace_updates, nil)
  end

  def matches_read?(socket, params) when is_map(params) and map_size(params) == 3,
    do: matches?(socket, params)

  def matches_read?(_, _), do: false

  def matches_action?(socket, %{"event" => event, "input" => input} = params)
      when map_size(params) == 5 and is_map(input) and event in @events,
      do: matches?(socket, params)

  def matches_action?(_, _), do: false

  defp matches?(socket, %{"path" => path, "id" => @id, "token" => token}) do
    scope = socket.assigns.current_scope

    case socket.assigns[:ops_command_workspace_session] do
      %{identity: {org, user, mission, ^path}, token: ^token} ->
        path == socket.assigns.host_path and org == scope.organization_id and
          user == scope.user.user_id and scope.mission_id in [nil, mission]

      _ ->
        false
    end
  end

  defp matches?(_, _), do: false

  def read(socket) do
    {page, session} =
      snapshot(socket.assigns.current_scope, socket.assigns.ops_command_workspace_session)

    {page, Component.assign(socket, :ops_command_workspace_session, session)}
  end

  def action(socket, event, input) do
    scope = socket.assigns.current_scope
    session = socket.assigns.ops_command_workspace_session
    {_, _, mission, _} = session.identity

    {result, session} =
      case RequestAuthoring.authorize(scope, mission) do
        {:ok, _, _} ->
          Session.action(scope, session, event, input)

        _ ->
          {%{
             status: "rejected",
             feedback: "Command preparation is unavailable with your current access."
           }, session}
      end

    {result, Component.assign(socket, :ops_command_workspace_session, session)}
  end

  defp snapshot(scope, session) do
    {org, _, mission, _} = session.identity

    envelope = %{
      id: @id,
      slot: "ops.page",
      version: 1,
      token: session.token,
      context: %{organizationId: org, missionId: mission}
    }

    case Session.load(scope, session) do
      {:ok, data, session} -> {Map.merge(envelope, %{status: "ready", data: data}), session}
      _ -> {Map.put(envelope, :status, "unavailable"), session}
    end
  rescue
    _ ->
      {%{id: @id, slot: "ops.page", version: 1, token: session.token, status: "unavailable"},
       session}
  end
end
