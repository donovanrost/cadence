defmodule CadenceWeb.OpsCommandReviewPage do
  @moduledoc "Host-bound command review visits with finite decisions and receipt recovery."
  alias Cadence.Management.Commanding.RequestReview
  alias Cadence.Reads.CommandReview
  alias Phoenix.Component
  @route "/missions/:mission_id/ops/commands/requests/:command_request_id"
  @id "commanding.review"

  def prepare(socket, %{route: @route, params: params}, path) do
    scope = socket.assigns.current_scope

    identity =
      {scope.organization_id, scope.user.user_id, params["mission_id"],
       params["command_request_id"], path}

    session =
      case socket.assigns[:ops_command_review_session] do
        %{identity: ^identity} = previous ->
          previous

        _ ->
          %{
            identity: identity,
            token: Ecto.UUID.generate(),
            query: Map.drop(params, ["mission_id", "command_request_id"]),
            model: nil,
            operation: nil
          }
      end

    {page, session} = snapshot(scope, session)
    Component.assign(socket, ops_command_review_session: session, ops_page: page)
  end

  def prepare(socket, _, _), do: Component.assign(socket, :ops_command_review_session, nil)

  def matches_read?(socket, p) when is_map(p) and map_size(p) == 3, do: matches?(socket, p)
  def matches_read?(_, _), do: false

  def matches_action?(socket, %{"event" => "decide", "input" => input} = p)
      when map_size(p) == 5 and is_map(input), do: matches?(socket, p)

  def matches_action?(_, _), do: false

  defp matches?(socket, %{"path" => path, "id" => @id, "token" => token}) do
    scope = socket.assigns.current_scope

    case socket.assigns[:ops_command_review_session] do
      %{identity: {org, user, mission, _, ^path}, token: ^token} ->
        path == socket.assigns.host_path and org == scope.organization_id and
          user == scope.user.user_id and scope.mission_id in [nil, mission]

      _ ->
        false
    end
  end

  defp matches?(_, _), do: false

  def read(socket) do
    {page, session} =
      snapshot(socket.assigns.current_scope, socket.assigns.ops_command_review_session)

    {page, Component.assign(socket, :ops_command_review_session, session)}
  end

  def action(socket, "decide", %{"expected_review" => review} = input) do
    session = socket.assigns.ops_command_review_session

    if is_nil(session.operation) and is_map(session.model) and session.model["can_decide"] and
         session.model["expected_review"] == review do
      session = %{session | operation: %{status: "unconfirmed"}}
      socket = Component.assign(socket, :ops_command_review_session, session)
      {_, _, mission, request, _} = session.identity
      operation = perform(socket.assigns.current_scope, mission, request, input)

      {operation,
       Component.assign(socket, :ops_command_review_session, %{session | operation: operation})}
    else
      {%{
         status: "rejected",
         feedback:
           "This page can no longer submit a decision. Return to Commands and reopen the request."
       }, socket}
    end
  end

  def action(socket, _, _),
    do: {%{status: "rejected", feedback: "Invalid review decision."}, socket}

  defp perform(scope, mission, request, input) do
    case RequestReview.decide(scope, mission, request, input) do
      {:ok, receipt} -> %{status: "completed", receipt: receipt}
      {:rejected, feedback} -> %{status: "rejected", feedback: feedback}
    end
  rescue
    _ -> %{status: "unconfirmed"}
  catch
    _, _ -> %{status: "unconfirmed"}
  end

  defp snapshot(scope, session) do
    {org, _, mission, request, _} = session.identity

    page = %{
      id: @id,
      slot: "ops.page",
      version: 1,
      token: session.token,
      context: %{organizationId: org, missionId: mission, resourceId: request}
    }

    case CommandReview.load(scope, mission, request, session.query) do
      {:ok, review} ->
        {Map.merge(page, %{status: "ready", data: %{review: review, operation: session.operation}}),
         %{session | model: review}}

      _ ->
        {Map.put(page, :status, "unavailable"), %{session | model: nil}}
    end
  end
end
