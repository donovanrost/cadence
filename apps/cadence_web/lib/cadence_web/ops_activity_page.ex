defmodule CadenceWeb.OpsActivityPage do
  @moduledoc """
  Host placement and page-instance admission for dashboard history.

  History is read-only: every save is the current version, and comparing or
  restoring versions happens on the dashboard page (`CadenceWeb.OpsDashboardPage`).
  """
  alias Cadence.Reads.Dashboards.Activity
  alias Phoenix.Component
  @route "/missions/:mission_id/ops/dashboards/:dashboard_id/activity"
  @id "dashboards.activity"

  def prepare(socket, %{route: @route, params: params}, path) do
    scope = socket.assigns.current_scope
    mission = params["mission_id"]
    dashboard = params["dashboard_id"]
    identity = {scope.organization_id, scope.user.user_id, mission, dashboard, path}
    query = Map.drop(params, ~w(mission_id dashboard_id))

    session =
      case socket.assigns[:ops_activity_session] do
        %{identity: ^identity} = previous ->
          previous

        _ ->
          %{
            identity: identity,
            token: Ecto.UUID.generate(),
            sequence: 0,
            phase: "ready",
            model: nil,
            query: query
          }
      end

    put_session(socket, %{session | model: model(Activity.load(scope, mission, dashboard, query))})
  end

  def prepare(socket, _, _), do: Component.assign(socket, :ops_activity_session, nil)

  def matches?(socket, %{"id" => @id, "path" => path, "token" => token}) do
    scope = socket.assigns.current_scope

    case socket.assigns[:ops_activity_session] do
      %{identity: {org, user, mission, _, ^path}, token: ^token} ->
        path == socket.assigns.host_path and org == scope.organization_id and
          user == scope.user.user_id and scope.mission_id in [nil, mission]

      _ ->
        false
    end
  end

  def matches?(_, _), do: false

  def action(socket, event, input) do
    session = socket.assigns.ops_activity_session

    case admit(session, event, input) do
      {:ok, command} ->
        session = %{session | sequence: input["sequence"], phase: "review"}
        {status, code, session} = effect(socket.assigns.current_scope, session, event, command)
        {%{status: status, code: code, state: state(session)}, put_session(socket, session)}

      _ ->
        {%{status: "rejected", code: nil, state: state(session)}, socket}
    end
  end

  defp admit(session, event, %{"sequence" => sequence, "command" => command} = input)
       when map_size(input) == 2 and is_integer(sequence) and sequence in 1..1_000_000 and
              is_map(command) do
    if sequence == session.sequence + 1,
      do: admit_command(session, event, command),
      else: :error
  end

  defp admit(_, _, _), do: :error

  defp admit_command(_session, "reload_activity", command) when command == %{},
    do: {:ok, command}

  defp admit_command(_, _, _), do: :error

  defp effect(scope, session, "reload_activity", _) do
    case read(scope, session) do
      {:ok, model} -> {"ok", nil, %{session | model: model, phase: "ready"}}
      _ -> {"unknown", nil, %{session | model: nil}}
    end
  end

  defp read(scope, session) do
    {_, _, mission, dashboard, _} = session.identity
    Activity.load(scope, mission, dashboard, session.query)
  end

  defp model({:ok, model}), do: model
  defp model(_), do: nil
  defp state(session), do: Map.take(session, [:sequence, :phase, :model])

  defp put_session(socket, session) do
    {org, _, mission, dashboard, _} = session.identity

    page = %{
      id: @id,
      slot: "ops.page",
      version: 1,
      token: session.token,
      context: %{organizationId: org, missionId: mission, resourceId: dashboard},
      status: if(session.model, do: "ready", else: "unavailable")
    }

    page = if session.model, do: Map.put(page, :data, state(session)), else: page
    Component.assign(socket, ops_activity_session: session, ops_page: page)
  end
end
