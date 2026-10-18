defmodule CadenceWeb.OpsPlanReviewPage do
  @moduledoc "Authenticated plan review, pinned reads and serialized decision receipt recovery."
  alias Cadence.Applications.JSONBoundary
  alias Cadence.Applications.OpsConsole.Actions.NativePlanningInput
  alias Cadence.Applications.OpsConsole.Actions.PlanReviewWorkflow, as: Workflow
  alias Cadence.Auth.Policy
  alias Cadence.Missions
  alias Cadence.Reads.ApplicationSurfaces.Planning.ContactPlanShow
  alias Phoenix.Component
  @route "/missions/:mission_id/ops/plans/:contact_plan_id"
  @id "planning.plan-review"

  def prepare(socket, %{route: @route, params: params}, path) do
    scope = socket.assigns.current_scope
    identity = {scope.organization_id, scope.user.user_id, params["mission_id"], path}

    session =
      case socket.assigns[:ops_plan_review_session] do
        %{identity: ^identity} = previous ->
          previous

        _ ->
          %{
            identity: identity,
            token: Ecto.UUID.generate(),
            params: Map.delete(params, "mission_id"),
            model: nil,
            sequence: 0,
            operation: nil
          }
      end

    {page, session} = snapshot(scope, session)
    Component.assign(socket, ops_plan_review_session: session, ops_page: page)
  end

  def prepare(socket, _, _),
    do: Component.assign(socket, :ops_plan_review_session, nil)

  def matches_read?(socket, p) when is_map(p) and map_size(p) == 3, do: matches?(socket, p)
  def matches_read?(_, _), do: false

  def matches_action?(socket, %{"event" => event, "input" => input} = p)
      when map_size(p) == 5 and is_map(input),
      do:
        matches?(socket, p) and
          event in Workflow.actions()

  def matches_action?(_, _), do: false

  defp matches?(socket, %{"path" => path, "id" => @id, "token" => token}) do
    scope = socket.assigns.current_scope

    case socket.assigns[:ops_plan_review_session] do
      %{identity: {org, user, mission, ^path}, token: ^token} ->
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
      snapshot(socket.assigns.current_scope, socket.assigns.ops_plan_review_session)

    {page, Component.assign(socket, :ops_plan_review_session, session)}
  end

  def action(socket, event, %{"sequence" => sequence, "payload" => input} = request)
      when map_size(request) == 2 and is_integer(sequence) and sequence in 1..1_000_000 and
             is_map(input) do
    session = socket.assigns.ops_plan_review_session

    with true <- is_map(session.model),
         true <- sequence == session.sequence + 1,
         true <- is_nil(session.operation) or session.operation.status != "unconfirmed",
         {:ok, input} <- NativePlanningInput.admit(input) do
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

    session = %{session | sequence: sequence, operation: operation}
    socket = Component.assign(socket, :ops_plan_review_session, session)
    {_, _, mission, _} = session.identity

    result = effect(socket.assigns.current_scope, mission, event, input, session.model)

    operation = complete(operation, result)

    session = %{session | operation: operation}

    {operation, Component.assign(socket, :ops_plan_review_session, session)}
  end

  defp effect(scope, mission, event, input, model) do
    Workflow.execute(scope, mission, event, input, model)
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

  defp complete(operation, {:rejected, feedback}),
    do: Map.merge(operation, %{status: "rejected", feedback: feedback})

  defp complete(operation, _), do: operation

  defp snapshot(scope, session) do
    {org, _, mission, _} = session.identity

    page = %{
      id: @id,
      slot: "ops.page",
      version: 1,
      token: session.token,
      context: %{
        organizationId: org,
        missionId: mission,
        resourceId: session.params["contact_plan_id"]
      }
    }

    with :ok <-
           Policy.authorize(scope, :operate_mission, %{organization_id: org, mission_id: mission}),
         {:ok, mission} <- Missions.fetch_mission(org, mission),
         {:ok, %{detail: detail}} <- ContactPlanShow.load(scope, mission, session.params),
         {:ok, detail} <- JSONBoundary.safe_workflow_output(detail) do
      data = %{
        detail: detail,
        actor_id: scope.user.user_id,
        sequence: session.sequence,
        operation: session.operation
      }

      params = Map.put(session.params, "version", Integer.to_string(detail["plan"]["version"]))

      {Map.merge(page, %{status: "ready", data: data}),
       %{session | model: detail, params: params}}
    else
      _ -> {Map.put(page, :status, "unavailable"), %{session | model: nil}}
    end
  end
end
