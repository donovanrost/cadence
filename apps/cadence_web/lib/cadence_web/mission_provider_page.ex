defmodule CadenceWeb.MissionProviderPage do
  @moduledoc "Mission-provider placement and page-instance effect admission."
  alias Cadence.Auth.Policy
  alias Cadence.Control.Providers, as: ControlProviders
  alias Cadence.GroundNetworks.MissionProviderRegistration
  alias Cadence.Management.Providers
  alias Cadence.Reads.Comms.MissionProviders

  @routes %{
    "/missions/:mission_id/comms/providers" => "provider_list",
    "/missions/:mission_id/comms/providers/new" => "provider_new",
    "/missions/:mission_id/comms/providers/:provider_id" => "provider_show"
  }
  @effects ~w(create-provider validate-provider sync-provider archive-provider)

  def prepare(socket, %{route: route, params: params}, path) do
    case Map.fetch(@routes, route) do
      {:ok, page} -> prepare_page(socket, page, params, path)
      :error -> Phoenix.Component.assign(socket, :mission_provider_session, nil)
    end
  end

  defp prepare_page(socket, page, params, path) do
    scope = socket.assigns.current_scope
    mission = params["mission_id"]
    identity = {scope.organization_id, scope.user.user_id, mission, path}

    session =
      case socket.assigns[:mission_provider_session] do
        %{identity: ^identity, page: ^page} = previous ->
          previous

        _ ->
          %{
            identity: identity,
            page: page,
            token: Ecto.UUID.generate(),
            sequence: 0,
            phase: :editing,
            model: nil,
            params: read_params(page, params),
            resource: params["provider_id"]
          }
      end

    result =
      if page == "provider_new" and session.model,
        do: {:ok, session.model},
        else: MissionProviders.load(scope, mission, page, session.params)

    envelope = %{
      id: id(page),
      slot: "mission.page",
      version: 1,
      context:
        Map.merge(
          %{organizationId: scope.organization_id, missionId: mission},
          if(page == "provider_show", do: %{resourceId: session.resource}, else: %{})
        )
    }

    {session, snapshot} =
      case result do
        {:ok, model} ->
          session = %{session | model: model}
          data = if page == "provider_list", do: model, else: session_data(session)
          {session, Map.merge(envelope, %{status: "ready", data: data, token: session.token})}

        _ ->
          {session, Map.merge(envelope, %{status: "unavailable", token: session.token})}
      end

    Phoenix.Component.assign(socket,
      mission_provider_session: session,
      mission_module_page: snapshot
    )
  end

  def matches?(socket, %{"id" => id, "token" => token, "path" => path}) do
    scope = socket.assigns.current_scope

    case socket.assigns[:mission_provider_session] do
      %{identity: {org, user, mission, ^path}, token: ^token, page: page} ->
        id == id(page) and path == socket.assigns.host_path and org == scope.organization_id and
          user == scope.user.user_id and (is_nil(scope.mission_id) or scope.mission_id == mission)

      _ ->
        false
    end
  end

  def matches?(_socket, _input), do: false

  def action(socket, "refresh", input) when input == %{} do
    session = socket.assigns.mission_provider_session
    {_, _, mission, _} = session.identity

    case MissionProviders.load(
           socket.assigns.current_scope,
           mission,
           session.page,
           session.params
         ) do
      {:ok, model} ->
        session = %{session | model: model}

        {%{status: "ok", sequence: session.sequence, data: session_data(session)},
         Phoenix.Component.assign(socket, :mission_provider_session, session)}

      _ ->
        reply(socket, "rejected")
    end
  end

  def action(socket, event, input) when event in @effects and is_map(input) do
    session = socket.assigns.mission_provider_session
    {org, _, mission, _} = session.identity
    scope = socket.assigns.current_scope

    with true <-
           session.phase == :editing and is_integer(input["sequence"]) and
             input["sequence"] == session.sequence + 1 and
             session.sequence < 1_000_000,
         :ok <-
           Policy.authorize(scope, :manage_mission, %{organization_id: org, mission_id: mission}),
         {:ok, command} <- admit(scope, mission, session, event, input) do
      session = %{session | sequence: input["sequence"], phase: :submitted}
      socket = Phoenix.Component.assign(socket, :mission_provider_session, session)
      result = effect(scope, mission, event, command)

      phase =
        cond do
          result.status != "ok" -> :submitted
          event in ["create-provider", "archive-provider"] -> :completed
          true -> :editing
        end

      session = %{session | phase: phase}

      {Map.put(result, :sequence, session.sequence),
       Phoenix.Component.assign(socket, :mission_provider_session, session)}
    else
      _ -> reply(socket, "rejected")
    end
  end

  def action(socket, _event, _input), do: reply(socket, "rejected")

  defp admit(
         scope,
         mission,
         %{page: "provider_new", model: model},
         "create-provider",
         %{"provider" => params, "sequence" => _} = input
       )
       when map_size(input) == 2 and is_map(params) do
    bindings = get_in(model, ["data", "accounts", "bindings"]) || []
    binding = Enum.find(bindings, &(&1["grant_id"] == params["provider_account_grant_id"]))

    with true <- is_map(binding),
         true <- params["provider_account_id"] == binding["account_id"],
         true <- params["provider_account_version"] == to_string(binding["account_version"]),
         true <- params["provider_account_grant_version"] == to_string(binding["grant_version"]) do
      MissionProviderRegistration.prepare(scope, mission, params)
    else
      _ -> {:error, :invalid_binding}
    end
  end

  defp admit(
         scope,
         mission,
         %{page: "provider_show", resource: id},
         event,
         %{"provider_id" => id, "expected_provider_version" => version, "sequence" => _} = input
       )
       when event in ~w(validate-provider sync-provider archive-provider) and map_size(input) == 3 and
              is_integer(version) do
    with {:ok, provider} <- Providers.fetch_provider(scope.organization_id, mission, id),
         true <- provider.version == version do
      {:ok, id}
    else
      _ -> {:error, :stale_provider}
    end
  end

  defp admit(_scope, _mission, _session, _event, _input), do: {:error, :invalid_request}

  defp effect(scope, mission, event, command) do
    result =
      case event do
        "create-provider" -> Providers.persist_provider(scope, command)
        "validate-provider" -> ControlProviders.validate_current(scope, mission, command)
        "sync-provider" -> ControlProviders.sync_current(scope, mission, command)
        "archive-provider" -> Providers.archive_provider(scope, mission, command)
      end

    case result do
      {:ok, provider} ->
        %{
          status: "ok",
          data: %{
            result: %{
              provider_id: provider.provider_id,
              version: provider.version,
              display_name: provider.display_name
            }
          }
        }

      _ ->
        %{status: "unknown"}
    end
  rescue
    _ -> %{status: "unknown"}
  catch
    _, _ -> %{status: "unknown"}
  end

  defp reply(socket, status),
    do: {%{status: status, sequence: socket.assigns.mission_provider_session.sequence}, socket}

  defp session_data(session),
    do: %{model: session.model, phase: Atom.to_string(session.phase), sequence: session.sequence}

  defp read_params("provider_new", params),
    do: Map.take(params, ~w(provider_account_id provider_account_grant_id))

  defp read_params("provider_show", params), do: Map.take(params, ["provider_id"])
  defp read_params(_page, _params), do: %{}
  defp id(page), do: "comms." <> String.replace(page, "_", "-")
end
