defmodule CadenceWeb.OpsHistoricalWorkflowsPage do
  @moduledoc "Captured native history reads and serialized action response recovery."
  alias Cadence.Applications.JSONBoundary
  alias Cadence.Applications.OpsConsole.Actions.HistoricalWorkflowActions, as: Actions
  alias Cadence.Reads.ApplicationSurfaces.DataOperations.HistoricalWorkflows, as: Read
  alias Phoenix.Component

  @query_keys ~w(group page audit_page jobs_page origins_page bindings_page binding_q)

  @routes %{
    "/missions/:mission_id/ops/data-operations" => {"reader", "data-operations.history"},
    "/missions/:mission_id/ops/data-operations/manage" =>
      {"manage", "data-operations.history-manage"}
  }

  def prepare(socket, %{route: route, params: params}, path) when is_map_key(@routes, route) do
    {mode, id} = @routes[route]
    scope = socket.assigns.current_scope
    identity = {scope.organization_id, scope.user.user_id, params["mission_id"], path}

    session =
      case socket.assigns[:ops_history_session] do
        %{identity: ^identity} = previous ->
          previous

        _ ->
          %{
            identity: identity,
            mode: mode,
            id: id,
            token: Ecto.UUID.generate(),
            params: Map.take(params, @query_keys),
            defaults: Read.initial_defaults(),
            model: nil,
            review: nil,
            sequence: 0,
            operation: nil,
            read_error: false
          }
      end

    {page, session} = snapshot(scope, session)
    Component.assign(socket, ops_history_session: session, ops_page: page)
  end

  def prepare(socket, _, _), do: Component.assign(socket, :ops_history_session, nil)

  def matches_read?(socket, params) when is_map(params) and map_size(params) == 3,
    do: matches?(socket, params)

  def matches_read?(_, _), do: false

  def matches_action?(socket, %{"event" => event, "input" => input} = params)
      when map_size(params) == 5 and is_map(input),
      do: matches?(socket, params) and event in Actions.actions()

  def matches_action?(_, _), do: false

  defp matches?(socket, %{"path" => path, "id" => id, "token" => token}) do
    scope = socket.assigns.current_scope

    case socket.assigns[:ops_history_session] do
      %{identity: {org, actor, mission, ^path}, id: ^id, token: ^token} ->
        socket.assigns.host_path == path and org == scope.organization_id and
          actor == scope.user.user_id and scope.mission_id in [nil, mission]

      _ ->
        false
    end
  end

  defp matches?(_, _), do: false

  def read(socket) do
    {page, session} = snapshot(socket.assigns.current_scope, socket.assigns.ops_history_session)
    {page, Component.assign(socket, :ops_history_session, session)}
  end

  def action(socket, event, %{"sequence" => sequence, "payload" => input} = request)
      when map_size(request) == 2 and is_integer(sequence) and sequence in 1..1_000_000 and
             is_map(input) do
    session = socket.assigns.ops_history_session

    if action_ready?(session, event, sequence) and Actions.admit_input(event, input) == :ok do
      perform(socket, session, event, sequence, input)
    else
      {%{status: "rejected"}, socket}
    end
  end

  def action(socket, _, _), do: {%{status: "rejected"}, socket}

  defp action_ready?(session, event, sequence) do
    is_map(session.model) and sequence == session.sequence + 1 and
      (is_nil(session.operation) or session.operation.status != "unconfirmed") and
      (not session.read_error or event == "read-page")
  end

  defp perform(socket, session, event, sequence, input) do
    operation = %{
      id: Ecto.UUID.generate(),
      action: event,
      sequence: sequence,
      input: input,
      status: "unconfirmed",
      result: nil,
      feedback: []
    }

    {_, _, mission, _} = session.identity
    result = effect(socket.assigns.current_scope, mission, session, operation)
    {operation, session} = complete(operation, session, result)
    session = %{session | sequence: sequence, operation: operation}
    {operation, Component.assign(socket, :ops_history_session, session)}
  end

  defp effect(scope, mission, session, operation) do
    Actions.execute(
      scope,
      mission,
      session.mode,
      session,
      operation.action,
      operation.input,
      operation.id
    )
  rescue
    _ -> :unconfirmed
  catch
    _, _ -> :unconfirmed
  end

  defp complete(operation, session, {:page, model, review, query}) do
    {%{operation | status: "completed", result: %{page_changed: true}},
     %{session | model: model, review: review, params: query, read_error: false}}
  end

  defp complete(operation, session, {:ok, result}),
    do: {%{operation | status: "completed", result: result}, select_result(session, result)}

  defp complete(operation, session, {:rejected, feedback}),
    do: {%{operation | status: "rejected", feedback: feedback}, session}

  defp complete(operation, session, {:unconfirmed, result}),
    do: {%{operation | result: result}, select_result(session, result)}

  defp complete(operation, session, _), do: {operation, session}

  defp select_result(session, %{group_id: group}),
    do: %{session | params: Map.put(session.params, "group", group)}

  defp select_result(session, _), do: session

  defp snapshot(scope, session) do
    {org, actor, mission, _} = session.identity

    page = %{
      id: session.id,
      slot: "ops.page",
      version: 1,
      token: session.token,
      context: %{organizationId: org, missionId: mission}
    }

    case load(scope, mission, session) do
      {:ok, session} ->
        data = %{
          model: session.model,
          actor_id: actor,
          sequence: session.sequence,
          operation: session.operation,
          read_error: session.read_error
        }

        case JSONBoundary.safe_workflow_output(data) do
          {:ok, data} -> {Map.merge(page, %{status: "ready", data: data}), session}
          _ -> {Map.put(page, :status, "unavailable"), %{session | model: nil}}
        end

      _ ->
        {Map.put(page, :status, "unavailable"), %{session | model: nil}}
    end
  end

  defp load(scope, mission, session) do
    case Read.load(scope, mission, session.mode, session.params, session.defaults) do
      {:ok, model, review} ->
        {:ok, %{session | model: model, review: review, read_error: false}}

      {:error, {:request_group_not_found, _}} when not is_nil(session.operation) ->
        case Read.load(
               scope,
               mission,
               session.mode,
               Map.delete(session.params, "group"),
               session.defaults
             ) do
          {:ok, model, review} ->
            {:ok, %{session | model: model, review: review, read_error: true}}

          error ->
            error
        end

      error ->
        error
    end
  end
end
