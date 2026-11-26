defmodule CadenceWeb.OpsFleetWorkflowPage do
  @moduledoc "Captured host placement for reviewed fleet creation and run actions."
  alias Cadence.Applications.{ActionRequest, HostContext, JSONBoundary}
  alias Cadence.Applications.OpsConsole.Actions.FleetPlanning
  alias Cadence.Missions
  alias Cadence.Reads.ApplicationSurfaces.Planning.{FleetRun, FleetStart}
  alias Phoenix.Component

  @routes %{
    "/missions/:mission_id/ops/planning/new" => {"planning.fleet-start", "fleet_planning_new"},
    "/missions/:mission_id/ops/planning/runs/:fleet_planning_run_id" =>
      {"planning.fleet-run", "fleet_planning_run"}
  }
  @actions %{
    "planning.fleet-start" => ["validate-fleet-run", "create-fleet-run"],
    "planning.fleet-run" => ["refresh-fleet-run", "repair-fleet-run"]
  }

  def prepare(socket, %{route: route, params: params}, path) when is_map_key(@routes, route) do
    scope = socket.assigns.current_scope
    {id, surface} = @routes[route]
    identity = {scope.organization_id, scope.user.user_id, params["mission_id"], path}

    session =
      case socket.assigns[:ops_fleet_workflow_session] do
        %{identity: ^identity} = previous ->
          previous

        _ ->
          %{
            identity: identity,
            id: id,
            surface: surface,
            token: Ecto.UUID.generate(),
            params: Map.delete(params, "mission_id"),
            model: nil,
            review: nil,
            submitted: MapSet.new()
          }
      end

    {page, session} = snapshot(scope, session)
    Component.assign(socket, ops_fleet_workflow_session: session, ops_page: page)
  end

  def prepare(socket, _, _), do: Component.assign(socket, :ops_fleet_workflow_session, nil)

  def matches_read?(socket, request) when is_map(request) and map_size(request) == 3,
    do: matches?(socket, request)

  def matches_read?(_, _), do: false

  def matches_action?(socket, %{"event" => event, "input" => input} = request)
      when map_size(request) == 5 and is_map(input) do
    matches?(socket, request) and event in Map.get(@actions, request["id"], [])
  end

  def matches_action?(_, _), do: false

  defp matches?(socket, %{"path" => path, "id" => id, "token" => token}) do
    scope = socket.assigns.current_scope

    case socket.assigns[:ops_fleet_workflow_session] do
      %{identity: {org, user, mission, ^path}, id: ^id, token: ^token} ->
        path == socket.assigns.host_path and org == scope.organization_id and
          user == scope.user.user_id and (is_nil(scope.mission_id) or scope.mission_id == mission)

      _ ->
        false
    end
  end

  defp matches?(_, _), do: false

  def read(socket) do
    {page, session} =
      snapshot(socket.assigns.current_scope, socket.assigns.ops_fleet_workflow_session)

    {page, Component.assign(socket, :ops_fleet_workflow_session, %{session | review: nil})}
  end

  def action(socket, event, input) do
    session = socket.assigns.ops_fleet_workflow_session

    if admitted?(session, event, input) do
      perform(socket, session, event, input)
    else
      {%{status: "rejected"}, socket}
    end
  end

  defp admitted?(%{model: nil}, _, _), do: false

  defp admitted?(%{id: "planning.fleet-start"} = session, "validate-fleet-run", _),
    do: not MapSet.member?(session.submitted, "create-fleet-run")

  defp admitted?(
         %{id: "planning.fleet-start", review: review} = session,
         "create-fleet-run",
         input
       )
       when is_map(review),
       do:
         not MapSet.member?(session.submitted, "create-fleet-run") and
           input["fleet_run"] === review.window and input["evidence"] === review.evidence

  defp admitted?(%{id: "planning.fleet-run"} = session, event, input)
       when event in ["refresh-fleet-run", "repair-fleet-run"] do
    model = session.model

    evidence =
      if event == "refresh-fleet-run",
        do: model["evidence"],
        else: get_in(model, ["repair", "evidence"])

    available =
      if event == "refresh-fleet-run",
        do: model["can_continue"],
        else: get_in(model, ["repair", "available"])

    not MapSet.member?(session.submitted, event) and available == true and
      input["fleet_planning_run_id"] == session.params["fleet_planning_run_id"] and
      is_map(evidence) and input["evidence"] === evidence
  end

  defp admitted?(_, _, _), do: false

  defp perform(socket, session, "validate-fleet-run" = event, input) do
    result = execute(socket.assigns.current_scope, session, event, input)

    review =
      case result do
        {:ok, %{"review" => %{"evidence" => evidence}}} ->
          %{window: input["fleet_run"], evidence: evidence}

        _ ->
          nil
      end

    {completion(result),
     Component.assign(socket, :ops_fleet_workflow_session, %{session | review: review})}
  end

  defp perform(socket, session, event, input) do
    # Consume before entering governed effects, including an uncertain result.
    session = %{session | submitted: MapSet.put(session.submitted, event), review: nil}
    socket = Component.assign(socket, :ops_fleet_workflow_session, session)
    {completion(execute(socket.assigns.current_scope, session, event, input)), socket}
  end

  defp execute(scope, session, event, input) do
    {_, _, mission, _} = session.identity

    request = %ActionRequest{
      application_key: "ops_console",
      application_version: 1,
      surface_id: session.surface,
      surface_version: 1,
      action_id: event,
      params: input
    }

    FleetPlanning.execute(scope, HostContext.mission(mission), session.surface, request)
  rescue
    _ -> {:error, :unavailable}
  catch
    _, _ -> {:error, :unavailable}
  end

  defp completion({:ok, result}),
    do: %{
      receiptId: Ecto.UUID.generate(),
      completedAt: DateTime.to_iso8601(DateTime.utc_now()),
      result: result
    }

  defp completion(_), do: %{status: "unconfirmed"}

  defp snapshot(scope, session) do
    {org, _, mission, _} = session.identity
    context = %{organizationId: org, missionId: mission}

    context =
      case session.params["fleet_planning_run_id"] do
        nil -> context
        run -> Map.put(context, :resourceId, run)
      end

    page = %{id: session.id, slot: "ops.page", version: 1, token: session.token, context: context}

    with {:ok, entity} <- Missions.fetch_mission(org, mission),
         {:ok, model} <- load(scope, entity, session),
         {:ok, data} <- JSONBoundary.safe(model) do
      {Map.merge(page, %{status: "ready", data: data}), %{session | model: data}}
    else
      _ -> {Map.put(page, :status, "unavailable"), %{session | model: nil, review: nil}}
    end
  end

  defp load(scope, mission, %{id: "planning.fleet-start", params: params})
       when map_size(params) == 0 do
    with {:ok, %{start: start}} <- FleetStart.load(scope, mission), do: {:ok, start}
  end

  defp load(scope, mission, %{id: "planning.fleet-run", params: params}) do
    with {:ok, %{run: run}} <- FleetRun.load(scope, mission, params), do: {:ok, run}
  end

  defp load(_, _, _), do: {:error, :invalid_query}
end
