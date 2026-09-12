defmodule CadenceWeb.OpsSettingsPage do
  @moduledoc "Host placement and page-instance admission for dashboard settings."
  alias Cadence.Dashboards.SettingsAuthoring
  alias Cadence.Reads.Dashboards.Settings
  alias Phoenix.Component
  @route "/missions/:mission_id/ops/dashboards/:dashboard_id/settings"
  @id "dashboards.settings"

  def prepare(socket, %{route: @route, params: params}, path) do
    scope = socket.assigns.current_scope
    mission = params["mission_id"]
    dashboard = params["dashboard_id"]
    identity = {scope.organization_id, scope.user.user_id, mission, dashboard, path}
    query = Map.drop(params, ~w(mission_id dashboard_id))

    session =
      case socket.assigns[:ops_settings_session] do
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

    session =
      case read(scope, session) do
        {:ok, model} -> %{session | model: model}
        _ -> %{session | phase: "review"}
      end

    put_session(socket, session)
  end

  def prepare(socket, _, _), do: Component.assign(socket, :ops_settings_session, nil)

  def matches?(socket, %{"id" => @id, "path" => path, "token" => token}) do
    scope = socket.assigns.current_scope

    case socket.assigns[:ops_settings_session] do
      %{identity: {org, user, mission, _, ^path}, token: ^token} ->
        path == socket.assigns.host_path and org == scope.organization_id and
          user == scope.user.user_id and scope.mission_id in [nil, mission]

      _ ->
        false
    end
  end

  def matches?(_, _), do: false

  def action(socket, "page_settings", input) when is_map(input) do
    session = socket.assigns.ops_settings_session
    {_, _, mission, dashboard, _} = session.identity

    case Settings.load(socket.assigns.current_scope, mission, dashboard, input) do
      {:ok, model} ->
        session = %{session | model: model, query: input}
        {reply("ok", nil, session), put_session(socket, session)}

      _ ->
        {reply("unknown", nil, session), socket}
    end
  end

  def action(socket, event, input) do
    session = socket.assigns.ops_settings_session

    case admit(session, event, input) do
      {:ok, command} ->
        session = %{session | sequence: input["sequence"], phase: "review"}
        {status, receipt, session} = effect(socket.assigns.current_scope, session, event, command)
        {reply(status, receipt, session), put_session(socket, session)}

      _ ->
        {reply("rejected", nil, session), socket}
    end
  end

  defp reply(status, receipt, session),
    do: %{status: status, receipt: receipt, state: state(session)}

  defp admit(session, event, %{"sequence" => sequence, "command" => command} = input)
       when map_size(input) == 2 and is_integer(sequence) and sequence in 1..1_000_000 and
              is_map(command) do
    if sequence == session.sequence + 1, do: admit_command(session, event, command), else: :error
  end

  defp admit(_, _, _), do: :error
  defp admit_command(_, "reload_settings", command) when command == %{}, do: {:ok, command}

  defp admit_command(%{phase: "ready", model: %{lifecycle: "active"} = model}, event, command)
       when event in [
              "save_settings",
              "create_share",
              "revoke_share",
              "create_snapshot",
              "archive_dashboard"
            ] do
    if command["expected_version"] == model.document_version and
         command["expected_revision"] == model.revision, do: {:ok, command}, else: :error
  end

  defp admit_command(_, _, _), do: :error

  defp effect(scope, session, "reload_settings", _) do
    case read(scope, session) do
      {:ok, model} -> {"ok", nil, %{session | model: model, phase: "ready"}}
      _ -> {"unknown", nil, session}
    end
  end

  defp effect(scope, session, event, command) do
    {_, _, mission, dashboard, _} = session.identity

    case SettingsAuthoring.execute(scope, mission, dashboard, event, command) do
      {:ok, receipt} ->
        session =
          case read(scope, session) do
            {:ok, model} -> %{session | model: model}
            _ -> session
          end

        {"ok", receipt, session}

      {:error, :invalid_input} ->
        {"invalid", nil, %{session | phase: "ready"}}

      {:error, :conflict} ->
        {"conflict", nil, session}

      _ ->
        {"unknown", nil, session}
    end
  end

  defp read(scope, session) do
    {_, _, mission, dashboard, _} = session.identity
    Settings.load(scope, mission, dashboard, session.query)
  end

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
    Component.assign(socket, ops_settings_session: session, ops_page: page)
  end
end
