defmodule Cadence.Dashboards.DirectoryActions do
  @moduledoc """
  Scoped dashboard directory commands; frontend loading never grants authority.

  Any mission operator can star a dashboard for themselves. Archiving, restoring
  and duplicating change shared dashboards, so they need dashboard authorship.
  """
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

  defp command(scope, mission, event, %{"dashboard_id" => id} = input)
       when event in ~w(archive restore) and map_size(input) == 1 and is_binary(id) and
              byte_size(id) in 1..256 do
    with :ok <- authorize_author(scope, mission),
         :ok <- lifecycle(event, scope, mission, id) do
      {:ok, %{dashboard_id: id, archived: event == "archive"}}
    end
  end

  defp command(scope, mission, "duplicate", %{"dashboard_id" => id, "name" => name} = input)
       when map_size(input) == 2 and is_binary(id) and byte_size(id) in 1..256 and
              is_binary(name) do
    name = String.trim(name)

    with true <- name != "" and byte_size(name) <= 512,
         :ok <- authorize_author(scope, mission),
         {:ok, created} <-
           Dashboards.clone_document(scope.organization_id, mission, id,
             name: name,
             actor_id: scope.user.user_id
           ) do
      {:ok, %{dashboard_id: created.dashboard_id}}
    else
      false -> {:error, :invalid_name}
      error -> error
    end
  end

  defp command(_scope, _mission, _event, _input), do: {:error, :invalid_request}

  defp lifecycle("archive", scope, mission, id),
    do:
      Dashboards.archive_document(scope.organization_id, mission, id,
        actor_id: scope.user.user_id
      )

  defp lifecycle("restore", scope, mission, id),
    do:
      Dashboards.restore_document(scope.organization_id, mission, id,
        actor_id: scope.user.user_id
      )

  defp authorize_author(scope, mission),
    do:
      Policy.authorize(scope, :author_dashboards, %{
        organization_id: scope.organization_id,
        mission_id: mission
      })
end
