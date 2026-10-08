defmodule CadenceWeb.OpsContactSchedulingPage do
  @moduledoc "Captured scheduling, contact lineage and immutable provider-change review."
  alias Cadence.Applications.JSONBoundary
  alias Cadence.Applications.OpsConsole.Actions.ContactWorkflow, as: Workflow
  alias Cadence.Applications.OpsConsole.Actions.NativePlanningInput
  alias Cadence.Auth.Policy
  alias Cadence.Contacts.ScheduleOperations
  alias Cadence.Missions
  alias Cadence.Reads.ApplicationSurfaces.Planning.{ContactDetail, ContactRecord, ContactSchedule}
  alias Phoenix.Component

  @routes %{
    "/missions/:mission_id/ops/contacts" => {"schedule", "planning.contact-schedule", nil},
    "/missions/:mission_id/ops/contacts/records/:contact_id" =>
      {"record", "planning.contact-record", "contact_id"},
    "/missions/:mission_id/ops/contacts/:provider_reservation_id" =>
      {"reservation", "planning.reservation-review", "provider_reservation_id"}
  }

  def prepare(socket, %{route: route, params: params}, path) when is_map_key(@routes, route) do
    {kind, id, resource} = @routes[route]
    scope = socket.assigns.current_scope
    identity = {scope.organization_id, scope.user.user_id, params["mission_id"], path}

    session =
      case socket.assigns[:ops_contact_session] do
        %{identity: ^identity} = previous ->
          previous

        _ ->
          %{
            identity: identity,
            token: Ecto.UUID.generate(),
            kind: kind,
            id: id,
            resource: resource && params[resource],
            params: Map.delete(params, "mission_id"),
            model: nil,
            sequence: 0,
            operation: nil,
            search: nil,
            consumed: [],
            initial_window: nil,
            recovery: nil
          }
      end

    {page, session} = snapshot(scope, session)
    Component.assign(socket, ops_contact_session: session, ops_page: page)
  end

  def prepare(socket, _, _), do: Component.assign(socket, :ops_contact_session, nil)
  def matches_read?(socket, p) when is_map(p) and map_size(p) == 3, do: matches?(socket, p)
  def matches_read?(_, _), do: false

  def matches_action?(socket, %{"event" => event, "input" => input} = p)
      when map_size(p) == 5 and is_map(input) do
    matches?(socket, p) and event in Workflow.actions(socket.assigns.ops_contact_session.kind)
  end

  def matches_action?(_, _), do: false

  defp matches?(socket, %{"path" => path, "id" => id, "token" => token}) do
    scope = socket.assigns.current_scope

    case socket.assigns[:ops_contact_session] do
      %{identity: {org, user, mission, ^path}, id: ^id, token: ^token} ->
        path == socket.assigns.host_path and org == scope.organization_id and
          user == scope.user.user_id and scope.mission_id in [nil, mission]

      _ ->
        false
    end
  end

  defp matches?(_, _), do: false

  def read(socket) do
    {page, session} = snapshot(socket.assigns.current_scope, socket.assigns.ops_contact_session)
    {page, Component.assign(socket, :ops_contact_session, session)}
  end

  def action(socket, event, %{"contract_version" => 2} = request) do
    session = socket.assigns.ops_contact_session
    {_, _, mission, _} = session.identity

    result =
      if session.kind == "schedule" do
        ScheduleOperations.request(
          socket.assigns.current_scope,
          mission,
          event,
          request
        )
      else
        {:error, :unsupported_action}
      end

    case result do
      {:ok, result} -> {result, socket}
      _ -> {%{status: "rejected"}, socket}
    end
  end

  def action(socket, event, %{"sequence" => sequence, "payload" => input} = request)
      when map_size(request) == 2 and is_integer(sequence) and sequence in 1..1_000_000 and
             is_map(input) do
    session = socket.assigns.ops_contact_session

    with true <- is_map(session.model),
         true <- sequence == session.sequence + 1,
         true <- is_nil(session.operation) or session.operation.status != "unconfirmed",
         {:ok, input} <- NativePlanningInput.admit(input) do
      perform(socket, session, event, sequence, input)
    else
      _ -> {%{status: "rejected"}, socket}
    end
  end

  def action(socket, _, _), do: {%{status: "rejected"}, socket}

  defp perform(socket, session, event, sequence, input) do
    operation = %{
      sequence: sequence,
      action: event,
      input: input,
      status: "unconfirmed",
      receipt: nil
    }

    {_, _, mission, _} = session.identity
    result = effect(socket.assigns.current_scope, mission, session, event, input)
    {operation, recovery} = complete(operation, result)
    session = %{session | sequence: sequence, operation: operation, recovery: recovery}
    session = search_result(session, operation)

    consumed =
      if (event == "reserve" and session.search) &&
           Enum.any?(session.search["opportunities"], &(&1["token"] == input["token"])),
         do: Enum.uniq([input["token"] | session.consumed]),
         else: session.consumed

    {operation, Component.assign(socket, :ops_contact_session, %{session | consumed: consumed})}
  end

  defp effect(scope, mission, session, event, input) do
    Workflow.execute(scope, mission, session, event, input)
  rescue
    _ -> {:error, :unconfirmed}
  catch
    _, _ -> {:error, :unconfirmed}
  end

  defp complete(operation, {:ok, result}),
    do: {%{operation | status: "completed", receipt: receipt(result)}, nil}

  defp complete(operation, {:unconfirmed, result, recovery}),
    do: {%{operation | receipt: receipt(result)}, recovery}

  defp complete(operation, {:rejected, feedback}),
    do: {Map.merge(operation, %{status: "rejected", feedback: feedback}), nil}

  defp complete(operation, _), do: {operation, nil}

  defp receipt(result),
    do: %{
      receiptId: Ecto.UUID.generate(),
      completedAt: DateTime.to_iso8601(DateTime.utc_now()),
      result: result
    }

  defp search_result(session, %{
         action: "search",
         status: "completed",
         receipt: %{result: %{value: result}}
       }) do
    case JSONBoundary.safe_workflow_output(result) do
      {:ok, search} -> %{session | search: search, consumed: []}
      _ -> session
    end
  end

  defp search_result(session, _), do: session

  defp snapshot(scope, session) do
    {org, _, mission, _} = session.identity
    context = %{organizationId: org, missionId: mission}

    context =
      case session.resource do
        nil -> context
        resource -> Map.put(context, :resourceId, resource)
      end

    page = %{
      id: session.id,
      slot: "ops.page",
      version: 1,
      token: session.token,
      context: context
    }

    with :ok <-
           Policy.authorize(scope, :operate_mission, %{organization_id: org, mission_id: mission}),
         {:ok, subject} <- Missions.fetch_mission(org, mission),
         {:ok, model} <- load(scope, subject, session),
         {:ok, model} <- JSONBoundary.safe_workflow_output(model) do
      session = session |> pin(model) |> recover(scope, mission)

      data = %{
        kind: session.kind,
        model: session.model,
        actor_id: scope.user.user_id,
        sequence: session.sequence,
        operation: session.operation,
        search: session.search,
        consumed: session.consumed,
        operation_reservation: operation_reservation(scope, subject, session.operation)
      }

      {Map.merge(page, %{status: "ready", data: data}), session}
    else
      _ -> {Map.put(page, :status, "unavailable"), %{session | model: nil}}
    end
  end

  defp operation_reservation(scope, mission, %{
         action: action,
         receipt: %{result: %{value: value}}
       })
       when action in ["reserve", "cancel"] do
    with id when is_binary(id) <- value["providerReservationId"],
         {:ok, %{detail: detail}} <-
           ContactDetail.load(scope, mission, %{"provider_reservation_id" => id}),
         {:ok, detail} <- JSONBoundary.safe_workflow_output(detail),
         do: detail,
         else: (_ -> nil)
  end

  defp operation_reservation(_, _, _), do: nil

  defp load(scope, mission, %{kind: "schedule", params: params}) do
    with {:ok, %{schedule: model}} <- ContactSchedule.load(scope, mission, params),
         do: {:ok, model}
  end

  defp load(scope, mission, %{kind: "record", params: params}) do
    with {:ok, %{record: model}} <- ContactRecord.load(scope, mission, params), do: {:ok, model}
  end

  defp load(scope, mission, %{kind: "reservation", params: params}) do
    with {:ok, %{detail: model}} <- ContactDetail.load(scope, mission, params), do: {:ok, model}
  end

  defp pin(%{kind: "schedule"} = session, model) do
    window = session.initial_window || model["initial_window"]
    %{session | initial_window: window, model: Map.put(model, "initial_window", window)}
  end

  defp pin(session, model) do
    key = if session.kind == "record", do: "revision", else: "change_id"
    value = model["query"][key]
    params = if value, do: Map.put(session.params, key, to_string(value)), else: session.params
    %{session | model: model, params: params}
  end

  defp recover(
         %{operation: %{status: "unconfirmed"}, recovery: recovery} = session,
         scope,
         mission
       )
       when not is_nil(recovery) do
    case Workflow.recover(scope, mission, recovery) do
      {:ok, result} ->
        {operation, _} = complete(session.operation, {:ok, result})
        %{session | operation: operation, recovery: nil}

      _ ->
        session
    end
  end

  defp recover(session, _, _), do: session
end
