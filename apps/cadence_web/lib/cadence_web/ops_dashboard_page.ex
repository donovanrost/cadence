defmodule CadenceWeb.OpsDashboardPage do
  @moduledoc """
  Host lifetime of the Ops dashboard page: the live viewer and its in-place editor.

  `/dashboards/:id` views the dashboard; `/dashboards/:id/edit` is the same page
  holding a server-owned `AuthoringDraft`. Every staged change is resolved
  immediately so the canvas shows the candidate; nothing persists until `save`,
  which makes a new current version (there is no publish step). Live delivery
  and edit-conflict notices are in `CadenceWeb.OpsDashboardPage.Updates`;
  action effects are in `CadenceWeb.OpsDashboardPage.Actions`.
  """
  alias Cadence.Dashboards
  alias Cadence.Dashboards.{AuthoringDraft, Document}
  alias Cadence.Reads.Dashboards.{DashboardPage, Editor, Versions}
  alias CadenceWeb.OpsDashboardPage.{Actions, Updates}
  alias CadenceWeb.OpsWorkspaceURL
  alias Phoenix.Component
  alias Phoenix.LiveView

  @view_route "/missions/:mission_id/ops/dashboards/:dashboard_id"
  @edit_route "/missions/:mission_id/ops/dashboards/:dashboard_id/edit"
  @id "dashboards.workspace"

  def id, do: @id

  def prepare(socket, %{route: route, params: params}, path)
      when route in [@view_route, @edit_route] do
    scope = socket.assigns.current_scope

    identity =
      {scope.organization_id, scope.user.user_id, params["mission_id"], params["dashboard_id"],
       path}

    mode = if route == @edit_route, do: :edit, else: :view

    {session, opened?} =
      case socket.assigns[:ops_dashboard_session] do
        %{identity: ^identity} = previous -> {previous, false}
        _ -> {new_session(identity, mode, params), true}
      end

    session =
      if mode == :edit and is_nil(session.draft), do: Actions.open(scope, session), else: session

    {page, session} = page(scope, session)
    if opened?, do: record_view(socket, scope, session, page)

    socket
    |> Component.assign(ops_dashboard_session: session, ops_page: page)
    |> Updates.sync(session, page)
  end

  def prepare(socket, _info, _path) do
    socket
    |> Updates.stop()
    |> Component.assign(:ops_dashboard_session, nil)
  end

  # Opening a dashboard (not a live refresh) feeds the directory's "Recently viewed".
  defp record_view(socket, scope, %{identity: {org, user, mission, dashboard, _}}, %{
         status: "ready"
       }) do
    if LiveView.connected?(socket) and scope.user.user_id == user,
      do: Dashboards.record_dashboard_view(org, mission, user, dashboard)
  end

  defp record_view(_socket, _scope, _session, _page), do: nil

  defp new_session(identity, mode, params) do
    %{
      identity: identity,
      token: Ecto.UUID.generate(),
      mode: mode,
      runtime: OpsWorkspaceURL.admit(Map.drop(params, ~w(mission_id dashboard_id))),
      draft: nil,
      sequence: 0
    }
  end

  def matches_action?(socket, %{"event" => event, "input" => input} = params)
      when map_size(params) == 5 and is_map(input),
      do: event in Actions.events() and matches?(socket, params)

  def matches_action?(_, _), do: false

  defp matches?(socket, %{"path" => path, "id" => @id, "token" => token}) do
    scope = socket.assigns.current_scope

    case socket.assigns[:ops_dashboard_session] do
      %{identity: {org, user, mission, _, ^path}, token: ^token} ->
        path == socket.assigns.host_path and org == scope.organization_id and
          user == scope.user.user_id and scope.mission_id in [nil, mission]

      _ ->
        false
    end
  end

  defp matches?(_, _), do: false

  def action(socket, event, input) do
    scope = socket.assigns.current_scope
    session = socket.assigns.ops_dashboard_session

    if Actions.query?(event),
      do: {Actions.query(scope, session, event, input), socket},
      else: effect(socket, scope, session, event, input)
  end

  defp effect(
         socket,
         scope,
         session,
         event,
         %{"sequence" => sequence, "command" => command} = input
       )
       when map_size(input) == 2 and is_integer(sequence) and is_map(command) do
    {status, code, session, result} =
      if sequence == session.sequence + 1,
        do: Actions.effect(scope, %{session | sequence: sequence}, event, command),
        else: {"rejected", nil, session, nil}

    {page, session} = page(scope, session)
    socket = Component.assign(socket, ops_dashboard_session: session, ops_page: page)
    {%{status: status, code: code, page: page, result: result}, socket}
  end

  defp effect(socket, _scope, _session, _event, _input),
    do: {%{status: "rejected", code: nil, result: nil}, socket}

  defp page(scope, session) do
    {org, _, mission, dashboard, _} = session.identity

    envelope = %{
      id: @id,
      slot: "ops.page",
      version: 1,
      token: session.token,
      context: %{organizationId: org, missionId: mission, resourceId: dashboard}
    }

    case load(scope, session) do
      {:ok, data} ->
        data =
          Map.merge(data, %{
            sequence: session.sequence,
            resolved_at: DateTime.to_iso8601(DateTime.utc_now())
          })

        {Map.merge(envelope, %{status: "ready", data: data}), session}

      {:error, _} ->
        {Map.put(envelope, :status, "unavailable"), session}
    end
  rescue
    _ ->
      {%{id: @id, slot: "ops.page", version: 1, token: session.token, status: "unavailable"},
       session}
  end

  defp load(_scope, %{runtime: {:error, _}}), do: {:error, :invalid_context}

  defp load(scope, %{mode: :view, runtime: {:ok, runtime}} = session) do
    {_, _, mission, dashboard, _} = session.identity

    with {:ok, view} <- DashboardPage.load(scope, mission, dashboard, runtime) do
      {:ok, Map.merge(view, %{mode: "view", edit: nil, live: Updates.policy(session, view)})}
    end
  end

  defp load(
         scope,
         %{mode: :edit, draft: %AuthoringDraft{} = draft, runtime: {:ok, runtime}} = session
       ) do
    with {:ok, view, staged} <- DashboardPage.staged(scope, draft, runtime) do
      edit = %{
        revision: draft.revision,
        dirty: AuthoringDraft.dirty?(draft),
        conflict: staged.conflict,
        document_version: Document.version(draft.baseline),
        changes: Versions.summary(draft.baseline, staged.document),
        outline: Editor.outline(staged.document)
      }

      {:ok, Map.merge(view, %{mode: "edit", edit: edit, live: Updates.policy(session, view)})}
    end
  end

  defp load(_scope, _session), do: {:error, :unavailable}
end
