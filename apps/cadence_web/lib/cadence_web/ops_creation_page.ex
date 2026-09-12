defmodule CadenceWeb.OpsCreationPage do
  @moduledoc "Host placement and page-instance admission for dashboard creation."
  alias Cadence.Dashboards.Creation
  alias Cadence.Reads.Dashboards.Creation, as: CreationRead
  alias Phoenix.Component
  @route "/missions/:mission_id/ops/dashboards/new"
  @id "dashboards.creation"

  def prepare(socket, %{route: @route, params: params}, path) do
    scope = socket.assigns.current_scope
    mission = params["mission_id"]
    identity = {scope.organization_id, scope.user.user_id, mission, path}

    session =
      case socket.assigns[:ops_creation_session] do
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

    result = CreationRead.load(scope, mission, Map.take(params, ~w(mode source_dashboard_id)))
    {session, page} = snapshot(session, result)
    Component.assign(socket, ops_creation_session: session, ops_page: page)
  end

  def prepare(socket, _info, _path), do: Component.assign(socket, :ops_creation_session, nil)

  def matches?(socket, %{"id" => @id, "path" => path, "token" => token}) do
    scope = socket.assigns.current_scope

    case socket.assigns[:ops_creation_session] do
      %{identity: {org, user, mission, ^path}, token: ^token} ->
        path == socket.assigns.host_path and org == scope.organization_id and
          user == scope.user.user_id and
          (is_nil(scope.mission_id) or scope.mission_id == mission)

      _ ->
        false
    end
  end

  def matches?(_, _), do: false

  def action(socket, input) do
    session = socket.assigns.ops_creation_session

    case admit(session, input) do
      {:ok, fields} ->
        session = %{session | sequence: input["sequence"], phase: :submitted}
        socket = Component.assign(socket, :ops_creation_session, session)
        {_, _, mission, _} = session.identity
        result = effect(socket.assigns.current_scope, mission, session.model, fields)
        phase = if result.status == "invalid", do: :editing, else: :submitted

        {Map.put(result, :sequence, session.sequence),
         Component.assign(socket, :ops_creation_session, %{session | phase: phase})}

      _ ->
        {%{status: "rejected", sequence: session.sequence}, socket}
    end
  end

  defp admit(
         %{phase: :editing, sequence: sequence, model: model},
         %{"sequence" => next, "dashboard" => fields, "source_version" => version} = input
       )
       when is_map(model) and is_integer(next) and next == sequence + 1 and next <= 1_000_000 and
              map_size(input) == 3 do
    expected = if model.source, do: model.source.version, else: nil
    if version === expected, do: {:ok, fields}, else: {:error, :stale}
  end

  defp admit(_, _), do: {:error, :invalid}

  defp effect(scope, mission, model, fields) do
    case Creation.create(scope, mission, model, fields) do
      {:ok, data} ->
        %{status: "ok", data: data}

      {:invalid, code} when code in [:fields, :document, :source_changed] ->
        %{status: "invalid", code: Atom.to_string(code)}

      _ ->
        %{status: "unknown"}
    end
  rescue
    _ -> %{status: "unknown"}
  catch
    _, _ -> %{status: "unknown"}
  end

  defp snapshot(session, result) do
    {org, _, mission, _} = session.identity

    page = %{
      id: @id,
      slot: "ops.page",
      version: 1,
      token: session.token,
      context: %{organizationId: org, missionId: mission}
    }

    case result do
      {:ok, model} ->
        {%{session | model: model},
         Map.merge(page, %{
           status: "ready",
           data: %{model: model, sequence: session.sequence, phase: Atom.to_string(session.phase)}
         })}

      _ ->
        {session, Map.put(page, :status, "unavailable")}
    end
  end
end
