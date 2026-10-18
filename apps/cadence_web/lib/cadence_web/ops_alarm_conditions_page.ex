defmodule CadenceWeb.OpsAlarmConditionsPage do
  @moduledoc "Host placement and captured read-only recovery for limit alarm conditions."
  alias Cadence.Reads.LimitAlarmConditions
  alias Phoenix.Component
  @route "/missions/:mission_id/ops/alarms"
  @id "limits.alarm-conditions"
  @query_keys ~w(severity state spacecraft_id query page spacecraft_page spacecraft_query)

  def prepare(socket, %{route: @route, params: params}, path) do
    scope = socket.assigns.current_scope
    mission = params["mission_id"]
    identity = {scope.organization_id, scope.user.user_id, mission, path}

    session =
      case socket.assigns[:ops_alarm_conditions_session] do
        %{identity: ^identity} = previous ->
          previous

        _ ->
          %{
            identity: identity,
            token: Ecto.UUID.generate(),
            params: Map.take(params, @query_keys)
          }
      end

    Component.assign(socket,
      ops_alarm_conditions_session: session,
      ops_page: snapshot(scope, session)
    )
  end

  def prepare(socket, _, _), do: Component.assign(socket, :ops_alarm_conditions_session, nil)

  def matches?(socket, %{"path" => path, "id" => @id, "token" => token} = request)
      when map_size(request) == 3 do
    scope = socket.assigns.current_scope

    case socket.assigns[:ops_alarm_conditions_session] do
      %{identity: {org, user, mission, ^path}, token: ^token} ->
        path == socket.assigns.host_path and org == scope.organization_id and
          user == scope.user.user_id and (is_nil(scope.mission_id) or scope.mission_id == mission)

      _ ->
        false
    end
  end

  def matches?(_, _), do: false

  def read(socket),
    do: snapshot(socket.assigns.current_scope, socket.assigns.ops_alarm_conditions_session)

  defp snapshot(scope, session) do
    {org, _, mission, _} = session.identity

    envelope = %{
      id: @id,
      slot: "ops.page",
      version: 1,
      token: session.token,
      context: %{organizationId: org, missionId: mission}
    }

    case LimitAlarmConditions.load(scope, mission, session.params) do
      {:ok, data} -> Map.merge(envelope, %{status: "ready", data: data})
      _ -> Map.put(envelope, :status, "unavailable")
    end
  end
end
