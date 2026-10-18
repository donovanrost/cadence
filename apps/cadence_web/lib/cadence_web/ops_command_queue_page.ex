defmodule CadenceWeb.OpsCommandQueuePage do
  @moduledoc "Host-bound command queue confirmation and exact persisted receipt recovery."
  alias Cadence.Control.Commanding.QueueSubmission
  alias Phoenix.Component
  @route "/missions/:mission_id/ops/commands/requests/:command_request_id/queue"
  @id "commanding.queue-submission"

  def prepare(socket, %{route: @route, params: params}, path) do
    scope = socket.assigns.current_scope

    identity =
      {scope.organization_id, scope.user.user_id, params["mission_id"],
       params["command_request_id"], path}

    session =
      case socket.assigns[:ops_command_queue_session] do
        %{identity: ^identity} = previous ->
          previous

        _ ->
          %{
            identity: identity,
            token: Ecto.UUID.generate(),
            query: Map.drop(params, ["mission_id", "command_request_id"]),
            model: nil,
            held: nil,
            operation: nil
          }
      end

    {page, session} = snapshot(scope, session)
    Component.assign(socket, ops_command_queue_session: session, ops_page: page)
  end

  def prepare(socket, _, _), do: Component.assign(socket, :ops_command_queue_session, nil)

  def matches_read?(socket, params) when is_map(params) and map_size(params) == 3,
    do: matches?(socket, params)

  def matches_read?(_, _), do: false

  def matches_action?(socket, %{"event" => "submit", "input" => input} = params)
      when map_size(params) == 5 and is_map(input), do: matches?(socket, params)

  def matches_action?(_, _), do: false

  defp matches?(socket, %{"path" => path, "id" => @id, "token" => token}) do
    scope = socket.assigns.current_scope

    case socket.assigns[:ops_command_queue_session] do
      %{identity: {org, user, mission, _, ^path}, token: ^token} ->
        path == socket.assigns.host_path and org == scope.organization_id and
          user == scope.user.user_id and scope.mission_id in [nil, mission]

      _ ->
        false
    end
  end

  defp matches?(_, _), do: false

  def read(socket) do
    {page, session} =
      snapshot(socket.assigns.current_scope, socket.assigns.ops_command_queue_session)

    {page, Component.assign(socket, :ops_command_queue_session, session)}
  end

  def action(socket, "submit", %{"expected_queue" => expected} = input)
      when map_size(input) == 1 do
    session = socket.assigns.ops_command_queue_session

    if is_nil(session.operation) and is_map(session.held) and session.held.token == expected do
      session = %{session | operation: %{status: "unconfirmed"}}
      socket = Component.assign(socket, :ops_command_queue_session, session)
      {_, _, mission, _, _} = session.identity
      operation = perform(socket.assigns.current_scope, mission, session.held, input)

      {operation,
       Component.assign(socket, :ops_command_queue_session, %{session | operation: operation})}
    else
      {rejected(
         "This visit can no longer queue the request. Refresh its receipt or return to Commands."
       ), socket}
    end
  end

  def action(socket, _, _), do: {rejected("Invalid command queue action."), socket}

  defp perform(scope, mission, held, input) do
    case QueueSubmission.submit(scope, mission, held, input) do
      {:ok, receipt} ->
        %{status: "completed", receipt: receipt}

      {:error, reason} ->
        case QueueSubmission.recover(scope, mission, held) do
          {:ok, receipt} -> %{status: "completed", receipt: receipt}
          _ -> rejected(feedback(reason))
        end
    end
  rescue
    _ -> %{status: "unconfirmed"}
  catch
    _, _ -> %{status: "unconfirmed"}
  end

  defp snapshot(scope, session) do
    {org, _, mission, request, _} = session.identity

    page = %{
      id: @id,
      slot: "ops.page",
      version: 1,
      token: session.token,
      context: %{organizationId: org, missionId: mission, resourceId: request}
    }

    with true <- session.query == %{},
         {:ok, loaded} <- QueueSubmission.load(scope, mission, request) do
      held = if is_nil(session.operation), do: loaded.held, else: session.held
      session = %{session | held: held, model: loaded.model}
      session = recover_operation(scope, mission, session)

      data = %{
        model: session.model,
        preview: QueueSubmission.public_preview(session.held),
        operation: session.operation
      }

      if byte_size(Jason.encode!(data)) <= 262_144,
        do: {Map.merge(page, %{status: "ready", data: data}), session},
        else: {Map.put(page, :status, "unavailable"), session}
    else
      _ -> {Map.put(page, :status, "unavailable"), session}
    end
  rescue
    _ ->
      {%{id: @id, slot: "ops.page", version: 1, token: session.token, status: "unavailable"},
       session}
  end

  defp recover_operation(
         scope,
         mission,
         %{operation: %{status: "unconfirmed"}, held: held} = session
       ) do
    case QueueSubmission.recover(scope, mission, held) do
      {:ok, receipt} -> %{session | operation: %{status: "completed", receipt: receipt}}
      _ -> session
    end
  end

  defp recover_operation(_, _, session), do: session
  defp rejected(message), do: %{status: "rejected", feedback: message}
  defp feedback(:unavailable), do: "The mission is unavailable or your access has changed."

  defp feedback(:approved_command_basis_changed),
    do: "The approved command changed. Refresh and review it again."

  defp feedback(:command_queue_changed),
    do: "The reviewed request changed. Refresh and review it again."

  defp feedback({:command_request_expired, _}),
    do: "The request expired before it could enter the queue."

  defp feedback({:command_request_not_queueable, _, _}),
    do: "The request is no longer available to queue. Refresh its current state."

  defp feedback(_),
    do: "The command was not queued by this attempt. Refresh its current state before continuing."
end
