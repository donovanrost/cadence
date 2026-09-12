defmodule CadenceWeb.OpsDiagnosticsPage do
  @moduledoc """
  Page-instance admission for a retained, explicitly refreshed diagnostics inspection.

  View-only selection changes retain evidence. Every preparation reauthorizes the
  current publication without resolving it; changing runtime context or refreshing
  explicitly obtains new evidence. Browser parameters never supply resolver options.
  """
  alias Cadence.Reads.Dashboards.ExecutionDiagnostics
  alias Cadence.Reads.Dashboards.Workspace
  alias CadenceWeb.OpsDiagnosticsURL
  alias Phoenix.Component
  @route "/missions/:mission_id/ops/dashboards/:dashboard_id/diagnostics"
  @id "dashboards.execution-diagnostics"

  def prepare(socket, info, path, opts \\ [])

  def prepare(socket, %{route: @route, params: params}, path, opts) do
    scope = socket.assigns.current_scope
    mission = params["mission_id"]
    dashboard = params["dashboard_id"]

    with {:ok, url} <- OpsDiagnosticsURL.admit(params),
         {:ok, version} <- ExecutionDiagnostics.current_version(scope, mission, dashboard) do
      identity =
        {scope.organization_id, scope.user.user_id, mission, dashboard, url.runtime_query}

      dto_version = ExecutionDiagnostics.dto_version()

      session =
        case socket.assigns[:ops_diagnostics_session] do
          %{identity: ^identity, model: %{version: ^dto_version} = model} = previous ->
            %{previous | publication_changed: model.document_version != version}

          _ ->
            new_session(scope, mission, dashboard, identity, url, path, opts)
        end

      put_session(socket, %{session | path: path, selection: url.selection})
    else
      _ ->
        requirement =
          with {:ok, _} <- OpsDiagnosticsURL.admit(params),
               {:ok, data} <- Workspace.publication_requirement(scope, mission, dashboard) do
            %{status: "ready", data: data, token: Ecto.UUID.generate()}
          else
            _ -> %{status: "unavailable"}
          end

        Component.assign(socket,
          ops_diagnostics_session: nil,
          ops_page:
            Map.merge(
              %{
                id: @id,
                slot: "ops.page",
                version: 1,
                status: "unavailable",
                context: %{
                  organizationId: scope.organization_id,
                  missionId: mission,
                  resourceId: dashboard
                }
              },
              requirement
            )
        )
    end
  end

  def prepare(socket, _, _, _), do: Component.assign(socket, :ops_diagnostics_session, nil)

  def matches?(socket, %{"id" => @id, "path" => path, "token" => token}) do
    scope = socket.assigns.current_scope
    dto_version = ExecutionDiagnostics.dto_version()

    case socket.assigns[:ops_diagnostics_session] do
      %{
        identity: {org, user, mission, _, _},
        path: ^path,
        token: ^token,
        model: %{version: ^dto_version}
      } ->
        path == socket.assigns.host_path and org == scope.organization_id and
          match?(%{user_id: ^user}, scope.user) and scope.mission_id in [nil, mission]

      _ ->
        false
    end
  end

  def matches?(_, _), do: false

  def action(socket, event, input, opts \\ []) do
    session = socket.assigns[:ops_diagnostics_session]

    case {session, authorized_session?(socket, session)} do
      {%{}, true} ->
        dispatch_action(socket, session, event, input, opts)

      {%{}, false} ->
        session = %{session | model: nil, publication_changed: false}
        {%{status: "unavailable", state: state(session)}, put_session(socket, session)}

      _ ->
        {%{status: "rejected", state: nil}, socket}
    end
  end

  defp authorized_session?(socket, %{
         identity: {org, user, mission, dashboard, _},
         path: path,
         model: %{version: version}
       }) do
    scope = socket.assigns.current_scope

    org == scope.organization_id and match?(%{user_id: ^user}, scope.user) and
      path == socket.assigns.host_path and
      match?({:ok, _}, ExecutionDiagnostics.current_version(scope, mission, dashboard)) and
      version == ExecutionDiagnostics.dto_version()
  end

  defp authorized_session?(_, _), do: false

  defp dispatch_action(socket, session, event, input, opts) do
    if admitted_action?(session, event, input) do
      scope = socket.assigns.current_scope
      {_, _, mission, dashboard, _} = session.identity
      session = %{session | sequence: input["sequence"]}
      model = load(scope, mission, dashboard, session.runtime, opts)
      session = %{session | model: model, publication_changed: false}
      status = if model, do: "ok", else: "unavailable"
      {%{status: status, state: state(session)}, put_session(socket, session)}
    else
      {%{status: "rejected", state: state(session)}, socket}
    end
  end

  defp admitted_action?(%{sequence: previous}, "inspect", %{"sequence" => sequence} = input)
       when map_size(input) == 1 and is_integer(sequence) and sequence in 1..1_000_000,
       do: sequence == previous + 1

  defp admitted_action?(_, _, _), do: false

  defp new_session(scope, mission, dashboard, identity, url, path, opts) do
    %{
      identity: identity,
      path: path,
      token: Ecto.UUID.generate(),
      sequence: 0,
      selection: url.selection,
      runtime: url.runtime,
      runtime_query: url.runtime_query,
      model: load(scope, mission, dashboard, url.runtime, opts),
      publication_changed: false
    }
  end

  defp load(scope, mission, dashboard, runtime, opts) do
    case ExecutionDiagnostics.load(
           scope,
           mission,
           dashboard,
           Keyword.put(opts, :runtime, runtime)
         ) do
      {:ok, model} -> model
      _ -> nil
    end
  end

  defp state(session),
    do: Map.take(session, [:model, :selection, :runtime_query, :publication_changed, :sequence])

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
    Component.assign(socket, ops_diagnostics_session: session, ops_page: page)
  end
end
