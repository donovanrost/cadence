defmodule CadenceWeb.CommunicationsSetupPage do
  @moduledoc "Page-instance admission for module-owned Communications setup forms."
  alias Cadence.Auth.Policy
  alias Cadence.Management.CommunicationsSetup
  alias Cadence.Reads.Comms.Pages

  @routes %{
    "/missions/:mission_id/comms/transports/new" => "transport_new",
    "/missions/:mission_id/comms/routing/new" => "routing_new",
    "/missions/:mission_id/comms/ground-stations/new" => "ground_station_new",
    "/missions/:mission_id/comms/ground-stations/:ground_station_id/edit" => "ground_station_edit"
  }

  def prepare(socket, %{route: route, params: params}, path) do
    case Map.fetch(@routes, route) do
      {:ok, form} -> prepare_form(socket, form, params, path)
      :error -> Phoenix.Component.assign(socket, :communications_setup_session, nil)
    end
  end

  defp prepare_form(socket, form, params, path) do
    scope = socket.assigns.current_scope
    identity = {scope.organization_id, scope.user.user_id, params["mission_id"], path}

    session =
      case socket.assigns[:communications_setup_session] do
        %{identity: ^identity, form: ^form} = previous -> {:ok, previous}
        _ -> new_session(scope, identity, form, params)
      end

    envelope = %{
      id: contribution_id(form),
      slot: "mission.page",
      version: 1,
      context: context(scope.organization_id, params["mission_id"], form, params)
    }

    {session, page} =
      case session do
        {:ok, session} ->
          {session,
           Map.merge(envelope, %{
             status: "ready",
             token: session.token,
             data: %{model: session.model, phase: Atom.to_string(session.phase)}
           })}

        _ ->
          {nil, Map.put(envelope, :status, "unavailable")}
      end

    Phoenix.Component.assign(socket,
      communications_setup_session: session,
      mission_module_page: page
    )
  end

  defp new_session(scope, identity, form, params) do
    query =
      Map.take(
        params,
        if(form == "routing_new", do: ["spacecraft_id"], else: ["ground_station_id"])
      )

    with {:ok, model} <- Pages.load(scope, params["mission_id"], form, query) do
      {:ok,
       %{
         identity: identity,
         form: form,
         token: Ecto.UUID.generate(),
         model: model,
         phase: :editing,
         validated: nil,
         resource_id: if(form == "ground_station_edit", do: params["ground_station_id"])
       }}
    end
  end

  def matches?(socket, %{"id" => id, "token" => token, "path" => path}) do
    scope = socket.assigns.current_scope

    case socket.assigns[:communications_setup_session] do
      %{identity: {org, user, mission, ^path}, token: ^token, form: form, phase: :editing} ->
        id == contribution_id(form) and path == socket.assigns.host_path and
          org == scope.organization_id and user == scope.user.user_id and
          (is_nil(scope.mission_id) or mission == scope.mission_id)

      _ ->
        false
    end
  end

  def matches?(_socket, _input), do: false

  def action(socket, event, input) when event in ["validate", "save"] do
    session = socket.assigns.communications_setup_session
    {org, user, mission, path} = session.identity
    scope = socket.assigns.current_scope

    with true <- session.phase == :editing and path == socket.assigns.host_path,
         true <- org == scope.organization_id and user == scope.user.user_id,
         :ok <-
           Policy.authorize(scope, :operate_mission, %{organization_id: org, mission_id: mission}),
         :ok <- pinned_resource(session, input) do
      perform(socket, event, input, mission)
    else
      _ -> {%{status: "rejected"}, socket}
    end
  end

  defp pinned_resource(%{form: "ground_station_edit", resource_id: id}, %{
         "ground_station" => values
       })
       when is_map(values) do
    if values["ground_station_id"] == id, do: :ok, else: {:error, :invalid_resource}
  end

  defp pinned_resource(%{form: "ground_station_edit"}, _input), do: {:error, :invalid_resource}
  defp pinned_resource(_session, _input), do: :ok

  defp perform(socket, "validate", input, mission) do
    session = %{socket.assigns.communications_setup_session | validated: nil}
    socket = Phoenix.Component.assign(socket, :communications_setup_session, session)

    case validate(socket.assigns.current_scope, mission, session.form, input) do
      {:ok, result} ->
        session = if result["valid"] == true, do: %{session | validated: input}, else: session

        {completed(result),
         Phoenix.Component.assign(socket, :communications_setup_session, session)}

      _ ->
        {%{status: "rejected"}, socket}
    end
  end

  defp perform(socket, "save", input, mission) do
    session = socket.assigns.communications_setup_session

    with true <- is_map(session.validated) and input === session.validated,
         {:ok, %{"valid" => true}} <-
           validate(socket.assigns.current_scope, mission, session.form, input) do
      # Consume before effects, including exceptions and uncertain/partial results.
      session = %{session | phase: :submitted, validated: nil}
      socket = Phoenix.Component.assign(socket, :communications_setup_session, session)
      result = save(socket.assigns.current_scope, mission, session.form, input)
      session = if result.status == "ok", do: %{session | phase: :completed}, else: session
      {result, Phoenix.Component.assign(socket, :communications_setup_session, session)}
    else
      _ -> {%{status: "rejected"}, socket}
    end
  end

  defp validate(scope, mission, form, input) do
    CommunicationsSetup.execute(scope, mission, form, "validate", input)
  rescue
    _ -> {:error, :invalid_input}
  end

  defp save(scope, mission, form, input) do
    case CommunicationsSetup.execute(scope, mission, form, "save", input) do
      {:ok, result} -> completed(result)
      _ -> %{status: "unknown"}
    end
  rescue
    _ -> %{status: "unknown"}
  catch
    _, _ -> %{status: "unknown"}
  end

  defp completed(result),
    do: %{
      status: "ok",
      data: %{
        receiptId: Ecto.UUID.generate(),
        completedAt: DateTime.to_iso8601(DateTime.utc_now()),
        result: result
      }
    }

  defp context(org, mission, "ground_station_edit", params),
    do: %{organizationId: org, missionId: mission, resourceId: params["ground_station_id"]}

  defp context(org, mission, _form, _params), do: %{organizationId: org, missionId: mission}
  defp contribution_id(form), do: "comms." <> String.replace(form, "_", "-")
end
