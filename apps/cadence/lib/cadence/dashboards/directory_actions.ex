defmodule Cadence.Dashboards.DirectoryActions do
  @moduledoc "Scoped dashboard directory commands; frontend loading never grants authority."
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Dashboards

  def execute(
        %Scope{organization_id: org, mission_id: scoped, user: %{user_id: user}} = scope,
        mission,
        event,
        input
      )
      when is_binary(org) and org != "" and is_binary(mission) and mission != "" and
             is_binary(user) and user != "" and (is_nil(scoped) or scoped == mission) do
    with :ok <-
           Policy.authorize(scope, :operate_mission, %{organization_id: org, mission_id: mission}) do
      command(scope, mission, event, input)
    end
  end

  def execute(_scope, _mission, _event, _input), do: {:error, :forbidden}

  defp command(scope, mission, "star", %{"dashboard_id" => id, "starred" => starred} = input)
       when map_size(input) == 2 and is_binary(id) and byte_size(id) in 1..256 and
              is_boolean(starred) do
    case Dashboards.set_dashboard_starred(
           scope.organization_id,
           mission,
           scope.user.user_id,
           id,
           starred
         ) do
      {:ok, preference} -> {:ok, %{dashboard_id: id, starred: preference.starred}}
      error -> error
    end
  end

  defp command(
         scope,
         mission,
         "restore",
         %{"dashboard_id" => id, "expected_version" => version} = input
       )
       when map_size(input) == 2 and is_binary(id) and byte_size(id) in 1..256 and
              is_integer(version) and version > 0 do
    with :ok <-
           Policy.authorize(scope, :author_dashboards, %{
             organization_id: scope.organization_id,
             mission_id: mission
           }),
         :ok <-
           Dashboards.restore_document(scope.organization_id, mission, id,
             expected_version: version,
             actor_id: scope.user.user_id
           ) do
      {:ok, %{dashboard_id: id, lifecycle: "active"}}
    end
  end

  defp command(_scope, _mission, _event, _input), do: {:error, :invalid_request}
end
