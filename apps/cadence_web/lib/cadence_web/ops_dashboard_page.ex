defmodule CadenceWeb.OpsDashboardPage do
  @moduledoc """
  Host lifetime of the Ops dashboard page: the live viewer and its in-place editor.

  `/dashboards/:id` views the dashboard; `/dashboards/:id/edit` is the same page
  holding a server-owned `AuthoringDraft`. Every staged change is resolved
  immediately so the canvas shows the candidate; nothing persists until `save`.
  Live delivery (view mode only) is a wake-up: the browser reads again through
  its captured page port. See `CadenceWeb.OpsDashboardPage.Updates`.
  """
  alias Cadence.Dashboards.{AuthoringDraft, Document, VersionAuthoring}
  alias Cadence.Reads.Dashboards.{DashboardPage, Editor, ObservableChoices}
  alias CadenceWeb.OpsDashboardPage.Updates
  alias CadenceWeb.OpsWorkspaceURL
  alias Phoenix.Component

  @view_route "/missions/:mission_id/ops/dashboards/:dashboard_id"
  @edit_route "/missions/:mission_id/ops/dashboards/:dashboard_id/edit"
  @id "dashboards.workspace"
  @stage_events ~w(rename add_section update_section remove_section move_section add_widget update_widget remove_widget layout runtime_defaults)
  @edit_events @stage_events ++ ~w(save discard search_observables)
  @events @edit_events ++ ~w(publish)
  @invalid ~w(invalid_input invalid_defaults missing_section missing_placement unsupported_widget invalid_widget invalid_type invalid_title invalid_options invalid_binding invalid_document capacity)a

  def id, do: @id

  def prepare(socket, %{route: route, params: params}, path)
      when route in [@view_route, @edit_route] do
    scope = socket.assigns.current_scope

    identity =
      {scope.organization_id, scope.user.user_id, params["mission_id"], params["dashboard_id"],
       path}

    mode = if route == @edit_route, do: :edit, else: :view

    session =
      case socket.assigns[:ops_dashboard_session] do
        %{identity: ^identity} = previous -> previous
        _ -> new_session(identity, mode, params)
      end

    session = if mode == :edit and is_nil(session.draft), do: open(scope, session), else: session
    {page, session} = page(scope, session)

    socket
    |> Component.assign(ops_dashboard_session: session, ops_page: page)
    |> Updates.sync(session, page)
  end

  def prepare(socket, _info, _path) do
    socket
    |> Updates.stop()
    |> Component.assign(:ops_dashboard_session, nil)
  end

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
      when map_size(params) == 5 and is_map(input) and event in @events,
      do: matches?(socket, params)

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

  def action(socket, "search_observables", input) do
    scope = socket.assigns.current_scope

    response =
      with %{mode: :edit, draft: %AuthoringDraft{} = draft} <-
             socket.assigns.ops_dashboard_session,
           {:ok, choices} <- ObservableChoices.staged(scope, draft, input) do
        %{status: "ok", choices: choices}
      else
        _ -> %{status: "unavailable"}
      end

    {response, socket}
  end

  def action(socket, event, %{"sequence" => sequence, "command" => command} = input)
      when map_size(input) == 2 and is_integer(sequence) and is_map(command) do
    scope = socket.assigns.current_scope
    session = socket.assigns.ops_dashboard_session

    {status, code, session} =
      if sequence == session.sequence + 1,
        do: effect(scope, %{session | sequence: sequence}, event, command),
        else: {"rejected", nil, session}

    {page, session} = page(scope, session)
    socket = Component.assign(socket, ops_dashboard_session: session, ops_page: page)
    {%{status: status, code: code, page: page}, socket}
  end

  def action(socket, _event, _input), do: {%{status: "rejected", code: nil}, socket}

  defp effect(scope, %{mode: :edit, draft: %AuthoringDraft{} = draft} = session, event, command)
       when event in @stage_events do
    AuthoringDraft.stage(scope, draft, event, command) |> applied(session)
  end

  defp effect(scope, %{mode: :edit, draft: %AuthoringDraft{} = draft} = session, "save", command),
    do: AuthoringDraft.save(scope, draft, command) |> applied(session)

  defp effect(
         scope,
         %{mode: :edit, draft: %AuthoringDraft{} = draft} = session,
         "discard",
         command
       ) do
    # Discarding after someone else saved adopts their version instead of failing.
    case AuthoringDraft.discard(scope, draft, command) do
      {:error, :conflict} -> {"ok", nil, reopen(scope, session)}
      result -> applied(result, session)
    end
  end

  defp effect(scope, session, "publish", %{"version" => version} = command)
       when map_size(command) == 1 and is_integer(version) do
    {_, _, mission, dashboard, _} = session.identity

    if is_nil(session.draft) or not AuthoringDraft.dirty?(session.draft) do
      case VersionAuthoring.publish_latest(scope, mission, dashboard, version) do
        {:ok, _receipt} ->
          {"ok", nil, reopen(scope, session)}

        {:error, :conflict} ->
          {"conflict", nil, session}

        {:error, code} when code in [:invalid_input, :invalid_document] ->
          {"invalid", Atom.to_string(code), session}

        _ ->
          {"unknown", nil, session}
      end
    else
      {"invalid", "unsaved_changes", session}
    end
  end

  defp effect(_scope, session, _event, _command), do: {"rejected", nil, session}

  defp applied({:ok, draft, _details}, session), do: {"ok", nil, %{session | draft: draft}}
  defp applied({:ok, draft}, session), do: {"ok", nil, %{session | draft: draft}}

  defp applied({:error, code}, session) when code in @invalid,
    do: {"invalid", Atom.to_string(code), session}

  defp applied({:error, :conflict}, session), do: {"conflict", nil, session}
  defp applied(_, session), do: {"unknown", nil, session}

  # Publishing moves the saved baseline; a held draft must observe the new version.
  defp reopen(scope, %{mode: :edit} = session), do: open(scope, %{session | draft: nil})
  defp reopen(_scope, session), do: session

  defp open(scope, session) do
    {_, _, mission, dashboard, _} = session.identity

    case AuthoringDraft.open(scope, mission, dashboard) do
      {:ok, draft} -> %{session | draft: draft}
      _ -> session
    end
  end

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
        outline: Editor.outline(staged.document)
      }

      {:ok, Map.merge(view, %{mode: "edit", edit: edit, live: Updates.policy(session, view)})}
    end
  end

  defp load(_scope, _session), do: {:error, :unavailable}
end
