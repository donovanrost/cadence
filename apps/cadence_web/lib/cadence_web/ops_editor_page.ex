defmodule CadenceWeb.OpsEditorPage do
  @moduledoc "Host lifetime and page-instance admission for a server-owned staged dashboard."
  alias Cadence.Dashboards.AuthoringDraft
  alias Cadence.Reads.Dashboards.{Editor, ObservableChoices}
  alias Phoenix.Component
  @route "/missions/:mission_id/ops/dashboards/:dashboard_id/edit"
  @id "dashboards.editor"
  @actions ~w(rename add_section update_section remove_section move_section add_widget update_widget remove_widget layout runtime_defaults save_draft discard_draft)
  @invalid ~w(invalid_input invalid_defaults missing_section missing_placement unsupported_widget invalid_widget invalid_type invalid_title invalid_options invalid_binding invalid_document capacity)a

  def prepare(socket, %{route: @route, params: params}, path) do
    scope = socket.assigns.current_scope
    mission = params["mission_id"]
    dashboard = params["dashboard_id"]
    identity = {scope.organization_id, scope.user.user_id, mission, dashboard, path}

    session =
      case socket.assigns[:ops_editor_session] do
        %{identity: ^identity, contract: 2} = previous ->
          previous

        _ ->
          %{
            identity: identity,
            contract: 2,
            token: Ecto.UUID.generate(),
            sequence: 0,
            phase: "editing",
            revision: 0,
            dirty: false,
            model: nil,
            draft: nil
          }
      end

    session =
      cond do
        Map.keys(params) -- ~w(mission_id dashboard_id) != [] -> clear(session)
        is_nil(session.draft) -> open(scope, session)
        true -> refresh(scope, session)
      end

    put_session(socket, session)
  end

  def prepare(socket, _, _), do: Component.assign(socket, :ops_editor_session, nil)

  def matches?(socket, %{"id" => @id, "path" => path, "token" => token}) do
    scope = socket.assigns.current_scope

    case socket.assigns[:ops_editor_session] do
      %{identity: {org, user, mission, _, ^path}, token: ^token, contract: 2} ->
        path == socket.assigns.host_path and org == scope.organization_id and
          user == scope.user.user_id and scope.mission_id in [nil, mission]

      _ ->
        false
    end
  end

  def matches?(_, _), do: false

  # Recheck authority even for malformed commands. A rejected action must not
  # return retained authoring content after access or resource availability is lost.
  def action(socket, event, input) do
    scope = socket.assigns.current_scope
    session = authority(scope, socket.assigns.ops_editor_session)

    if event == "search_observables" do
      response =
        case search(scope, session, input) do
          {:ok, choices} -> %{status: "ok", choices: choices}
          _ -> %{status: "unavailable"}
        end

      {response, put_session(socket, session)}
    else
      command_action(socket, scope, session, event, input)
    end
  end

  defp search(scope, %{phase: "editing", draft: %AuthoringDraft{} = draft}, input),
    do: ObservableChoices.staged(scope, draft, input)

  defp search(_, _, _), do: {:error, :unavailable}

  defp command_action(socket, scope, session, event, input) do
    case admit(session, event, input) do
      {:ok, command} ->
        session = %{session | sequence: input["sequence"], phase: "review"}
        {status, code, session} = effect(scope, session, event, command)
        {%{status: status, code: code, state: state(session)}, put_session(socket, session)}

      _ ->
        {%{status: "rejected", code: nil, state: state(session)}, put_session(socket, session)}
    end
  end

  defp admit(session, event, %{"sequence" => sequence, "command" => command} = input)
       when map_size(input) == 2 and is_integer(sequence) and sequence in 1..1_000_000 and
              is_map(command) do
    if sequence == session.sequence + 1, do: admit_command(session, event, command), else: :error
  end

  defp admit(_, _, _), do: :error

  defp admit_command(session, event, command) do
    cond do
      event == "reload_editor" and command == %{} -> {:ok, command}
      event not in @actions or session.phase != "editing" or is_nil(session.model) -> :error
      command["expected_version"] != session.model.document_version -> :error
      command["expected_revision"] != session.revision -> :error
      true -> {:ok, command}
    end
  end

  defp effect(scope, session, "reload_editor", _) do
    session = open(scope, %{session | phase: "editing"})

    if session.model && session.phase == "editing",
      do: {"ok", nil, session},
      else: {"unknown", nil, session}
  end

  defp effect(scope, session, event, command) do
    result =
      case event do
        "save_draft" -> AuthoringDraft.save(scope, session.draft, command)
        "discard_draft" -> AuthoringDraft.discard(scope, session.draft, command)
        _ -> AuthoringDraft.stage(scope, session.draft, event, command)
      end

    effect_result(scope, session, result)
  end

  defp effect_result(scope, session, result) do
    case result do
      {:ok, draft, _details} ->
        applied(scope, session, draft)

      {:ok, draft} ->
        applied(scope, session, draft)

      {:error, code} when code in @invalid ->
        {"invalid", Atom.to_string(code), %{session | phase: "editing"}}

      {:error, :conflict} ->
        {"conflict", nil, session}

      {:error, code} when code in [:forbidden, :unavailable] ->
        {"unknown", nil, clear(session)}

      _ ->
        {"unknown", nil, session}
    end
  end

  defp applied(scope, session, draft) do
    # Retain the successful transaction before preparing a browser projection.
    session = project(scope, %{session | draft: draft, phase: "editing"})

    if session.model && session.phase == "editing",
      do: {"ok", nil, session},
      else: {"unknown", nil, session}
  end

  defp open(scope, session) do
    {_, _, mission, dashboard, _} = session.identity

    case AuthoringDraft.open(scope, mission, dashboard) do
      {:ok, draft} -> project(scope, %{session | draft: draft})
      _ -> clear(session)
    end
  end

  defp refresh(scope, session) do
    case authority(scope, session, true) do
      %{phase: "editing", draft: %AuthoringDraft{}} = current -> project(scope, current)
      current -> current
    end
  end

  defp authority(scope, session, lock_conflict? \\ false)

  defp authority(scope, %{draft: %AuthoringDraft{} = draft} = session, lock_conflict?) do
    case AuthoringDraft.current(scope, draft) do
      {:ok, _} -> session
      {:error, :conflict} -> if(lock_conflict?, do: %{session | phase: "review"}, else: session)
      _ -> clear(session)
    end
  end

  defp authority(_, session, _), do: clear(session)

  defp project(scope, session) do
    case Editor.staged(scope, session.draft) do
      {:ok, read} -> %{session | model: read.model, revision: read.revision, dirty: read.dirty}
      {:error, :conflict} -> %{session | phase: "review"}
      _ -> clear(session)
    end
  end

  defp clear(session), do: %{session | draft: nil, model: nil, dirty: false, phase: "review"}

  defp state(session),
    do:
      session |> Map.take([:sequence, :phase, :revision, :dirty, :model]) |> Map.put(:version, 2)

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
    Component.assign(socket, ops_editor_session: session, ops_page: page)
  end
end
