defmodule CadenceWeb.OpsRequirementPage do
  @moduledoc "Authenticated requirement placement, captured reads and governed receipt recovery."
  alias Cadence.Applications.JSONBoundary
  alias Cadence.Applications.OpsConsole.Actions.RequirementWorkflow, as: Workflow
  alias Cadence.Auth.Policy
  alias Cadence.Missions
  alias Cadence.Reads.ApplicationSurfaces.Planning.{ContactRequirementShow, RequirementDirectory}
  alias Phoenix.Component

  @routes %{
    "/missions/:mission_id/ops/requirements" => "planning.requirement-directory",
    "/missions/:mission_id/ops/requirements/:contact_requirement_id" =>
      "planning.requirement-review"
  }

  def prepare(socket, %{route: route, params: params}, path) when is_map_key(@routes, route) do
    scope = socket.assigns.current_scope

    identity =
      {scope.organization_id, scope.user.user_id, params["mission_id"],
       params["contact_requirement_id"], path}

    session =
      case socket.assigns[:ops_requirement_session] do
        %{identity: ^identity} = previous ->
          previous

        _ ->
          %{
            identity: identity,
            id: Map.fetch!(@routes, route),
            token: Ecto.UUID.generate(),
            params: Map.delete(params, "mission_id"),
            model: nil,
            sequence: 0,
            operation: nil
          }
      end

    {page, session} = snapshot(scope, session)
    Component.assign(socket, ops_requirement_session: session, ops_page: page)
  end

  def prepare(socket, _, _), do: Component.assign(socket, :ops_requirement_session, nil)
  def matches_read?(socket, p) when is_map(p) and map_size(p) == 3, do: matches?(socket, p)
  def matches_read?(_, _), do: false

  def matches_action?(socket, %{"event" => event, "input" => input} = p)
      when map_size(p) == 5 and is_map(input),
      do:
        matches?(socket, p) and p["id"] == "planning.requirement-review" and
          event in Workflow.actions()

  def matches_action?(_, _), do: false

  defp matches?(socket, %{"path" => path, "id" => id, "token" => token}) do
    scope = socket.assigns.current_scope

    case socket.assigns[:ops_requirement_session] do
      %{identity: {org, user, mission, _resource, ^path}, token: ^token, id: ^id} ->
        path == socket.assigns.host_path and org == scope.organization_id and
          user == scope.user.user_id and
          (is_nil(scope.mission_id) or scope.mission_id == mission)

      _ ->
        false
    end
  end

  defp matches?(_, _), do: false

  def read(socket) do
    {page, session} =
      snapshot(socket.assigns.current_scope, socket.assigns.ops_requirement_session)

    {page, Component.assign(socket, :ops_requirement_session, session)}
  end

  def action(socket, event, %{"sequence" => sequence, "payload" => input} = request)
      when map_size(request) == 2 and is_integer(sequence) and sequence in 1..1_000_000 and
             is_map(input) do
    session = socket.assigns.ops_requirement_session

    with true <- sequence == session.sequence + 1,
         true <- is_nil(session.operation) or session.operation.status != "unconfirmed",
         {:ok, input} <- JSONBoundary.safe(input) do
      perform(socket, session, event, sequence, input)
    else
      _ -> {%{status: "rejected"}, socket}
    end
  end

  def action(socket, _, _), do: {%{status: "rejected"}, socket}

  defp perform(socket, session, event, sequence, input) do
    operation = %{
      sequence: sequence,
      action: event,
      input: input,
      status: "unconfirmed",
      receipt: nil
    }

    admitted = Workflow.admitted?(session.model, event, input)
    session = %{session | sequence: sequence, operation: operation}
    socket = Component.assign(socket, :ops_requirement_session, session)
    {_, _, mission, _, _} = session.identity

    result =
      if admitted,
        do: effect(socket.assigns.current_scope, mission, event, input),
        else: {:rejected, :unavailable_review}

    operation = complete(operation, result)
    session = %{session | operation: operation}
    {operation, Component.assign(socket, :ops_requirement_session, session)}
  end

  defp effect(scope, mission, event, input) do
    Workflow.execute(scope, mission, event, input)
  rescue
    _ -> {:error, :unconfirmed}
  catch
    _, _ -> {:error, :unconfirmed}
  end

  defp complete(operation, {:ok, result}),
    do: %{
      operation
      | status: "completed",
        receipt: %{
          receiptId: Ecto.UUID.generate(),
          completedAt: DateTime.to_iso8601(DateTime.utc_now()),
          result: result
        }
    }

  defp complete(operation, {:rejected, _}), do: %{operation | status: "rejected"}
  defp complete(operation, _), do: operation

  defp snapshot(scope, session) do
    {org, _, mission, resource, _} = session.identity
    context = %{organizationId: org, missionId: mission}
    context = if resource, do: Map.put(context, :resourceId, resource), else: context
    page = %{id: session.id, slot: "ops.page", version: 1, token: session.token, context: context}

    with {:ok, model} <- load(scope, mission, resource, session.params),
         {:ok, model} <- JSONBoundary.safe(model) do
      data =
        if resource,
          do: %{detail: model, sequence: session.sequence, operation: session.operation},
          else: model

      params =
        if resource,
          do:
            Map.put_new(session.params, "version", Integer.to_string(model["query"]["version"])),
          else: session.params

      {Map.merge(page, %{status: "ready", data: data}), %{session | model: model, params: params}}
    else
      _ -> {Map.put(page, :status, "unavailable"), %{session | model: nil}}
    end
  end

  defp load(scope, mission, nil, params), do: RequirementDirectory.load(scope, mission, params)

  defp load(scope, mission, resource, params) do
    with true <- is_nil(scope.mission_id) or scope.mission_id == mission,
         :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: scope.organization_id,
             mission_id: mission
           }),
         {:ok, entity} <- Missions.fetch_mission(scope.organization_id, mission),
         {:ok, %{detail: detail}} <-
           ContactRequirementShow.load(
             scope,
             entity,
             Map.put(params, "contact_requirement_id", resource)
           ) do
      {:ok, detail}
    else
      false -> {:error, :scope_mismatch}
      error -> error
    end
  end
end
