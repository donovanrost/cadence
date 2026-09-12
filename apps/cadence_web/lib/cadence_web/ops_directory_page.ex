defmodule CadenceWeb.OpsDirectoryPage do
  @moduledoc "Host placement and page-instance action admission for the dashboard directory."
  alias Cadence.Dashboards.DirectoryActions
  alias Cadence.Reads.Dashboards.Directory
  alias Phoenix.Component

  @route "/missions/:mission_id/ops/dashboards"
  @id "dashboards.directory"

  def prepare(socket, %{route: @route, params: params}, path) do
    scope = socket.assigns.current_scope
    mission = params["mission_id"]
    identity = {scope.organization_id, scope.user.user_id, mission, path}

    session =
      case socket.assigns[:ops_directory_session] do
        %{identity: ^identity} = previous ->
          previous

        _ ->
          %{
            identity: identity,
            token: Ecto.UUID.generate(),
            sequence: 0,
            phase: :editing,
            model: nil
          }
      end

    result = Directory.load(scope, mission, Map.take(params, ~w(query lifecycle tag sort page)))
    {session, snapshot} = snapshot(session, result)
    Component.assign(socket, ops_directory_session: session, ops_page: snapshot)
  end

  def prepare(socket, _info, _path),
    do: Component.assign(socket, ops_directory_session: nil, ops_page: nil)

  def matches?(socket, %{"id" => @id, "path" => path, "token" => token}) do
    scope = socket.assigns.current_scope

    case socket.assigns[:ops_directory_session] do
      %{identity: {org, user, mission, ^path}, token: ^token} ->
        path == socket.assigns.host_path and org == scope.organization_id and
          user == scope.user.user_id and
          (is_nil(scope.mission_id) or scope.mission_id == mission)

      _ ->
        false
    end
  end

  def matches?(_socket, _request), do: false

  def action(socket, event, input) when event in ~w(star restore) and is_map(input) do
    session = socket.assigns.ops_directory_session

    with true <-
           session.phase == :editing and is_integer(input["sequence"]) and
             input["sequence"] == session.sequence + 1 and session.sequence < 1_000_000,
         {:ok, command} <- admit(session.model, event, input) do
      session = %{session | sequence: input["sequence"], phase: :submitted}
      socket = Component.assign(socket, :ops_directory_session, session)
      {_, _, mission, _} = session.identity
      result = effect(socket.assigns.current_scope, mission, event, command)
      phase = if result.status == "ok", do: :editing, else: :submitted
      session = %{session | phase: phase}

      {Map.put(result, :sequence, session.sequence),
       Component.assign(socket, :ops_directory_session, session)}
    else
      _ -> rejected(socket)
    end
  end

  def action(socket, _event, _input), do: rejected(socket)

  defp admit(
         %{rows: rows} = model,
         event,
         %{"dashboard_id" => id, "expected_version" => version, "sequence" => _} = input
       )
       when is_integer(version) do
    case Enum.find(rows, &(&1.id == id)) do
      %{version: ^version} = row -> admit_command(model.author, row, event, input)
      _ -> {:error, :stale}
    end
  end

  defp admit(_model, _event, _input), do: {:error, :invalid_request}

  defp admit_command(_author, %{lifecycle: "active"}, "star", %{"starred" => starred} = input)
       when map_size(input) == 4 and is_boolean(starred),
       do: {:ok, Map.take(input, ~w(dashboard_id starred))}

  defp admit_command(true, %{lifecycle: "archived"}, "restore", input) when map_size(input) == 3,
    do: {:ok, Map.take(input, ~w(dashboard_id expected_version))}

  defp admit_command(_author, _row, _event, _input), do: {:error, :invalid_request}

  defp effect(scope, mission, event, command) do
    case DirectoryActions.execute(scope, mission, event, command) do
      {:ok, data} -> %{status: "ok", data: data}
      _ -> %{status: "unknown"}
    end
  rescue
    _ -> %{status: "unknown"}
  catch
    _, _ -> %{status: "unknown"}
  end

  defp rejected(socket),
    do: {%{status: "rejected", sequence: socket.assigns.ops_directory_session.sequence}, socket}

  defp snapshot(session, result) do
    {org, _, mission, _} = session.identity

    envelope = %{
      id: @id,
      slot: "ops.page",
      version: 1,
      token: session.token,
      context: %{organizationId: org, missionId: mission}
    }

    case result do
      {:ok, model} ->
        {%{session | model: model},
         Map.merge(envelope, %{
           status: "ready",
           data: %{model: model, sequence: session.sequence, phase: Atom.to_string(session.phase)}
         })}

      _ ->
        {session, Map.put(envelope, :status, "unavailable")}
    end
  end
end
