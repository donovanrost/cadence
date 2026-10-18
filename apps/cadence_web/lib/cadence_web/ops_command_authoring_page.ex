defmodule CadenceWeb.OpsCommandAuthoringPage do
  @moduledoc "Host-bound command drafts, server-held previews and finite request creation."
  alias Cadence.Management.Commanding.RequestAuthoring
  alias Phoenix.Component
  @route "/missions/:mission_id/ops/commands/new"
  @id "commanding.authoring"

  def prepare(socket, %{route: @route, params: params}, path) do
    scope = socket.assigns.current_scope
    identity = {scope.organization_id, scope.user.user_id, params["mission_id"], path}

    session =
      case socket.assigns[:ops_command_authoring_session] do
        %{identity: ^identity} = previous ->
          previous

        _ ->
          %{
            identity: identity,
            token: Ecto.UUID.generate(),
            query: Map.drop(params, ["mission_id"]),
            model: nil,
            preview: nil,
            operation: nil
          }
      end

    {page, session} = snapshot(scope, session)
    Component.assign(socket, ops_command_authoring_session: session, ops_page: page)
  end

  def prepare(socket, _, _), do: Component.assign(socket, :ops_command_authoring_session, nil)

  def matches_read?(socket, params) when is_map(params) and map_size(params) == 3,
    do: matches?(socket, params)

  def matches_read?(_, _), do: false

  def matches_action?(socket, %{"event" => event, "input" => input} = params)
      when event in ["preview", "create"] and map_size(params) == 5 and is_map(input),
      do: matches?(socket, params)

  def matches_action?(_, _), do: false

  defp matches?(socket, %{"path" => path, "id" => @id, "token" => token}) do
    scope = socket.assigns.current_scope

    case socket.assigns[:ops_command_authoring_session] do
      %{identity: {org, user, mission, ^path}, token: ^token} ->
        path == socket.assigns.host_path and org == scope.organization_id and
          user == scope.user.user_id and
          scope.mission_id in [nil, mission]

      _ ->
        false
    end
  end

  defp matches?(_, _), do: false

  def read(socket) do
    {page, session} =
      snapshot(socket.assigns.current_scope, socket.assigns.ops_command_authoring_session)

    {page, Component.assign(socket, :ops_command_authoring_session, session)}
  end

  def action(socket, "preview", input) do
    session = socket.assigns.ops_command_authoring_session

    if is_nil(session.operation) and matches_selection?(session.model, input) do
      session = %{session | preview: nil}
      {_, _, mission, _} = session.identity
      {result, held} = prepare_preview(socket.assigns.current_scope, mission, input)

      {result,
       Component.assign(socket, :ops_command_authoring_session, %{session | preview: held})}
    else
      {rejected("Refresh the model and choose a target and command before previewing."), socket}
    end
  end

  def action(socket, "create", %{"expected_preview" => expected} = input)
      when map_size(input) == 1 do
    session = socket.assigns.ops_command_authoring_session

    if is_nil(session.operation) and is_map(session.preview) and session.preview.token == expected do
      session = %{session | operation: %{status: "unconfirmed"}}
      socket = Component.assign(socket, :ops_command_authoring_session, session)
      {_, _, mission, _} = session.identity
      operation = perform_create(socket.assigns.current_scope, mission, session.preview, input)

      {operation,
       Component.assign(socket, :ops_command_authoring_session, %{session | operation: operation})}
    else
      {rejected(
         "This page can no longer create a request. Check its receipt or begin a new draft."
       ), socket}
    end
  end

  def action(socket, _, _), do: {rejected("Invalid command authoring action."), socket}

  defp matches_selection?(model, input) when is_map(model) do
    is_map(model["selected_target"]) and is_map(model["selected_command"]) and
      model["selected_command"]["supported"] and
      input["expected_basis"] == model["basis"]["token"] and
      input["source_endpoint_ref"] == model["selected_target"]["id"] and
      input["command_id"] == model["selected_command"]["id"]
  end

  defp matches_selection?(_, _), do: false

  defp prepare_preview(scope, mission, input) do
    case RequestAuthoring.preview(scope, mission, input) do
      {:ok, held} ->
        {%{status: "previewed", preview: RequestAuthoring.public_preview(held)}, held}

      {:error, reason} ->
        {rejected(feedback(reason)), nil}
    end
  rescue
    _ -> {rejected("The preview is unavailable. Refresh before trying again."), nil}
  catch
    _, _ -> {rejected("The preview is unavailable. Refresh before trying again."), nil}
  end

  defp perform_create(scope, mission, held, input) do
    case RequestAuthoring.create(scope, mission, held, input) do
      {:ok, receipt} ->
        %{status: "completed", receipt: receipt}

      {:error, reason} ->
        case RequestAuthoring.recover(scope, mission, held) do
          {:ok, receipt} -> %{status: "completed", receipt: receipt}
          _ -> rejected(feedback(reason))
        end
    end
  rescue
    _ -> %{status: "unconfirmed"}
  catch
    _, _ -> %{status: "unconfirmed"}
  end

  defp snapshot(scope, session) do
    {org, _, mission, _} = session.identity

    page = %{
      id: @id,
      slot: "ops.page",
      version: 1,
      token: session.token,
      context: %{organizationId: org, missionId: mission}
    }

    with {:ok, _, _} <- RequestAuthoring.authorize(scope, mission),
         {:ok, model} <- current_model(scope, mission, session) do
      session = recover_operation(scope, mission, %{session | model: model})
      session = invalidate_preview(session)

      data = %{
        catalog: model,
        preview: public_preview(session.preview),
        operation: session.operation
      }

      {Map.merge(page, %{status: "ready", data: data}), session}
    else
      {:error, :command_authoring_basis_unavailable} ->
        data = %{
          state: "command_model_required",
          version: 1,
          context: page.context,
          actor_id: scope.user.user_id
        }

        {Map.merge(page, %{status: "ready", data: data}), %{session | model: nil, preview: nil}}

      _ ->
        {Map.put(page, :status, "unavailable"), session}
    end
  rescue
    _ ->
      {%{id: @id, slot: "ops.page", version: 1, token: session.token, status: "unavailable"},
       session}
  end

  defp current_model(scope, mission, session) do
    case RequestAuthoring.load(scope, mission, session.query) do
      {:ok, model} -> {:ok, model}
      _ when not is_nil(session.operation) and is_map(session.model) -> {:ok, session.model}
      error -> error
    end
  end

  defp recover_operation(
         scope,
         mission,
         %{operation: %{status: "unconfirmed"}, preview: held} = session
       ) do
    case RequestAuthoring.recover(scope, mission, held) do
      {:ok, receipt} -> %{session | operation: %{status: "completed", receipt: receipt}}
      _ -> session
    end
  end

  defp recover_operation(_, _, session), do: session

  defp invalidate_preview(%{operation: nil, preview: held, model: model} = session)
       when is_map(held) do
    if held.expected_basis == model["basis"]["token"] and held.target == model["selected_target"],
      do: session,
      else: %{session | preview: nil}
  end

  defp invalidate_preview(session), do: session
  defp public_preview(nil), do: nil
  defp public_preview(held), do: RequestAuthoring.public_preview(held)
  defp rejected(message), do: %{status: "rejected", feedback: message}

  defp feedback(:command_authoring_basis_changed),
    do: "The active model or target changed. Refresh and review a new preview."

  defp feedback(:command_request_expired),
    do: "The request's expiry has passed. Begin a new draft with current timing."

  defp feedback(:unavailable), do: "The mission is unavailable or your access has changed."

  defp feedback(_),
    do:
      "The request could not be validated or saved. Check its arguments, refresh the model and review a new preview."
end
