defmodule CadenceWeb.OpsDirectoryPage do
  @moduledoc """
  Host lifetime of the dashboard directory.

  The page is the mission's dashboards for one person, filtered by the URL.
  Actions are sequenced like the dashboard page: each effect carries the next
  sequence number and is answered with the re-read page. The directory follows
  the mission live: any dashboard created, saved, archived or restored by
  anyone re-reads the page (bursts coalesce into one refresh).
  """
  alias Cadence.Dashboards.DirectoryActions
  alias Cadence.Platform.ScopedReadUpdates
  alias Cadence.Reads.Dashboards.Directory
  alias Phoenix.Component
  alias Phoenix.LiveView

  @route "/missions/:mission_id/ops/dashboards"
  @id "dashboards.directory"
  @filters ~w(query tags starred archived sort page lifecycle tag)
  @events ~w(star archive restore duplicate)
  @coalesce_ms 250

  def id, do: @id
  def events, do: @events

  def prepare(socket, %{route: @route, params: params}, path) do
    scope = socket.assigns.current_scope
    identity = {scope.organization_id, scope.user.user_id, params["mission_id"], path}

    session =
      case socket.assigns[:ops_directory_session] do
        %{identity: ^identity} = previous ->
          %{previous | filters: Map.take(params, @filters)}

        _ ->
          %{
            identity: identity,
            token: Ecto.UUID.generate(),
            sequence: 0,
            filters: Map.take(params, @filters),
            pending: nil
          }
      end

    socket
    |> follow(session)
    |> Component.assign(ops_directory_session: session, ops_page: page(scope, session))
  end

  def prepare(socket, _info, _path) do
    socket
    |> unfollow()
    |> Component.assign(ops_directory_session: nil)
  end

  def matches_action?(socket, %{"id" => @id, "event" => event, "input" => input} = params)
      when map_size(params) == 5 and is_map(input) and event in @events,
      do: matches?(socket, params)

  def matches_action?(_socket, _params), do: false

  defp matches?(socket, %{"path" => path, "token" => token}) do
    scope = socket.assigns.current_scope

    case socket.assigns[:ops_directory_session] do
      %{identity: {org, user, mission, ^path}, token: ^token} ->
        path == socket.assigns.host_path and org == scope.organization_id and
          user == scope.user.user_id and scope.mission_id in [nil, mission]

      _ ->
        false
    end
  end

  def action(socket, event, %{"sequence" => sequence, "command" => command} = input)
      when map_size(input) == 2 and is_integer(sequence) and is_map(command) do
    scope = socket.assigns.current_scope
    session = socket.assigns.ops_directory_session
    {_, _, mission, _} = session.identity

    {status, code, result, session} =
      if sequence == session.sequence + 1 do
        session = %{session | sequence: sequence}
        {status, code, result} = effect(scope, mission, event, command)
        {status, code, result, session}
      else
        {"rejected", nil, nil, session}
      end

    page = page(scope, session)
    socket = Component.assign(socket, ops_directory_session: session, ops_page: page)
    {%{status: status, code: code, page: page, result: result}, socket}
  end

  def action(socket, _event, _input),
    do: {%{status: "rejected", code: nil, result: nil}, socket}

  defp effect(scope, mission, event, command) do
    case DirectoryActions.execute(scope, mission, event, command) do
      {:ok, result} -> {"ok", nil, result}
      {:error, :invalid_name} -> {"invalid", "invalid_name", nil}
      {:error, reason} when reason in [:forbidden, :unauthorized] -> {"forbidden", nil, nil}
      _ -> {"unknown", nil, nil}
    end
  rescue
    _ -> {"unknown", nil, nil}
  end

  @doc "Another session changed this mission's dashboards; coalesce into one refresh."
  def changed(socket, org, mission) do
    case socket.assigns[:ops_directory_session] do
      %{identity: {^org, _, ^mission, _}, pending: nil, token: token} = session ->
        timer = Process.send_after(self(), {:dashboard_directory_flush, token}, @coalesce_ms)
        Component.assign(socket, :ops_directory_session, %{session | pending: timer})

      _ ->
        socket
    end
  end

  @doc "A coalesced change. Returns `{:refresh, socket}` while the page is current."
  def flush(socket, token) do
    case socket.assigns[:ops_directory_session] do
      %{token: ^token} = session ->
        {:refresh, Component.assign(socket, :ops_directory_session, %{session | pending: nil})}

      _ ->
        {:ignore, socket}
    end
  end

  defp follow(socket, %{identity: {org, _, mission, _}}) do
    following = {org, mission}

    cond do
      not LiveView.connected?(socket) ->
        socket

      socket.assigns[:ops_directory_following] == following ->
        socket

      true ->
        socket = unfollow(socket)
        :ok = ScopedReadUpdates.subscribe(:dashboards_changed, org, mission)
        Component.assign(socket, :ops_directory_following, following)
    end
  end

  defp unfollow(socket) do
    case socket.assigns[:ops_directory_following] do
      {org, mission} ->
        ScopedReadUpdates.unsubscribe(:dashboards_changed, org, mission)
        Component.assign(socket, :ops_directory_following, nil)

      _ ->
        socket
    end
  end

  defp page(scope, session) do
    {org, _, mission, _} = session.identity

    envelope = %{
      id: @id,
      slot: "ops.page",
      version: 1,
      token: session.token,
      context: %{organizationId: org, missionId: mission}
    }

    case Directory.load(scope, mission, session.filters) do
      {:ok, model} ->
        Map.merge(envelope, %{status: "ready", data: %{model: model, sequence: session.sequence}})

      _ ->
        Map.put(envelope, :status, "unavailable")
    end
  end
end
