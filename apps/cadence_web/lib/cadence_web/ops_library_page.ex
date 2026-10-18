defmodule CadenceWeb.OpsLibraryPage do
  @moduledoc "Host placement and observed-selection admission for the dashboard library."
  alias Cadence.Dashboards.LibraryAuthoring
  alias Cadence.Reads.Dashboards.Library
  alias Phoenix.Component
  @route "/missions/:mission_id/ops/dashboards/library"
  @id "dashboards.library"

  def prepare(socket, %{route: @route, params: params}, path) do
    scope = socket.assigns.current_scope
    mission = params["mission_id"]
    identity = {scope.organization_id, scope.user.user_id, mission, path}
    query = Map.delete(params, "mission_id")

    session =
      case socket.assigns[:ops_library_session] do
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

    model =
      case Library.load(scope, mission, query) do
        {:ok, model} -> model
        _ -> nil
      end

    put_session(socket, %{session | model: model})
  end

  def prepare(socket, _, _), do: Component.assign(socket, :ops_library_session, nil)

  def matches?(socket, %{"id" => @id, "path" => path, "token" => token}) do
    scope = socket.assigns.current_scope

    case socket.assigns[:ops_library_session] do
      %{identity: {org, user, mission, ^path}, token: ^token} ->
        path == socket.assigns.host_path and org == scope.organization_id and
          user == scope.user.user_id and scope.mission_id in [nil, mission]

      _ ->
        false
    end
  end

  def matches?(_, _), do: false

  def action(socket, event, input) do
    session = socket.assigns.ops_library_session

    case admit(session, event, input) do
      {:ok, command} ->
        session = %{session | sequence: input["sequence"], phase: "review"}

        {status, code, receipt, session} =
          effect(socket.assigns.current_scope, session, event, command)

        {%{status: status, code: code, receipt: receipt, state: state(session)},
         put_session(socket, session)}

      _ ->
        {%{status: "rejected", code: nil, receipt: nil, state: state(session)}, socket}
    end
  end

  defp admit(session, event, %{"sequence" => sequence, "command" => command} = input)
       when map_size(input) == 2 and is_integer(sequence) and sequence in 1..1_000_000 and
              is_map(command) do
    if sequence == session.sequence + 1, do: admit_command(session, event, command), else: :error
  end

  defp admit(_, _, _), do: :error
  defp admit_command(_, "reload_library", command) when command == %{}, do: {:ok, command}

  defp admit_command(%{phase: "ready", model: model}, event, command) when is_map(model) do
    if bound?(model, event, command), do: {:ok, command}, else: :error
  end

  defp admit_command(_, _, _), do: :error
  defp bound?(_, "create_item", _), do: true

  defp bound?(%{selected: %{item: item}}, "add_version", command),
    do: command["item_id"] == item.id and command["expected_version"] == item.latest_version

  defp bound?(
         %{selected: %{item: item, version: version}, target: target},
         "add_to_draft",
         command
       )
       when is_map(target),
       do:
         command == %{
           "item_id" => item.id,
           "version" => version,
           "dashboard_id" => target.id,
           "expected_version" => target.version
         }

  defp bound?(_, _, _), do: false

  defp effect(scope, session, "reload_library", _) do
    case read(scope, session) do
      {:ok, model} -> {"ok", nil, nil, %{session | model: model, phase: "ready"}}
      _ -> {"unknown", nil, nil, %{session | model: nil}}
    end
  end

  defp effect(scope, session, event, command) do
    {_, _, mission, _} = session.identity

    case LibraryAuthoring.execute(scope, mission, event, command) do
      {:ok, receipt} ->
        refresh_after_effect(scope, session, receipt)

      {:error, code} when code in [:invalid_input, :invalid_widget, :capacity] ->
        {"invalid", Atom.to_string(code), nil, %{session | phase: "ready"}}

      {:error, :conflict} ->
        {"conflict", nil, nil, session}

      _ ->
        {"unknown", nil, nil, session}
    end
  end

  defp refresh_after_effect(scope, session, receipt) do
    with {:ok, model} <- read(scope, session), true <- receipt_matches?(model, receipt) do
      {"ok", nil, receipt, %{session | model: model, phase: "ready"}}
    else
      _ -> {"unknown", nil, nil, session}
    end
  end

  defp receipt_matches?(_, %{event: "create_item"}), do: true

  defp receipt_matches?(%{selected: %{item: item}}, %{event: "add_version"} = receipt),
    do: item.id == receipt.item_id and item.latest_version == receipt.library_version

  defp receipt_matches?(%{target: target}, %{event: "add_to_draft"} = receipt)
       when is_map(target),
       do: target.id == receipt.dashboard_id and target.version == receipt.document_version

  defp receipt_matches?(_, _), do: false

  defp read(scope, session) do
    {_, _, mission, _} = session.identity
    Library.load(scope, mission, session.query)
  end

  defp state(session), do: Map.take(session, [:sequence, :phase, :model])

  defp put_session(socket, session) do
    {org, _, mission, _} = session.identity

    page = %{
      id: @id,
      slot: "ops.page",
      version: 1,
      token: session.token,
      context: %{organizationId: org, missionId: mission},
      status: if(session.model, do: "ready", else: "unavailable")
    }

    page = if session.model, do: Map.put(page, :data, state(session)), else: page
    Component.assign(socket, ops_library_session: session, ops_page: page)
  end
end
