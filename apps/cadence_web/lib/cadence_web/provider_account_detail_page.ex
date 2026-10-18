defmodule CadenceWeb.ProviderAccountDetailPage do
  @moduledoc "Account-bound organization-page transport with ordered effect admission."
  alias Cadence.GroundNetworks.ProviderAccountOperations
  alias Cadence.Reads.Comms.ProviderAccountDetail

  @id "comms.provider-account-detail"
  @actions %{
    "validate-account" => "validate_provider_account",
    "rotate-credential" => "rotate_provider_credential",
    "revoke-credential" => "revoke_provider_credential",
    "grant-mission" => "grant_provider_account_mission",
    "revoke-grant" => "revoke_provider_account_mission"
  }

  def prepare(socket, %{route: "/provider-accounts/:provider_account_id", params: params}, path) do
    scope = socket.assigns.current_scope
    account_id = params["provider_account_id"]

    session =
      case socket.assigns[:provider_detail_session] do
        %{path: ^path, account_id: ^account_id, organization_id: org, user_id: user} = previous
        when org == scope.organization_id and user == scope.user.user_id ->
          previous

        _ ->
          %{
            path: path,
            account_id: account_id,
            organization_id: scope.organization_id,
            user_id: scope.user.user_id,
            token: Ecto.UUID.generate(),
            sequence: 0,
            locked: false
          }
      end

    envelope = %{
      id: @id,
      slot: "organization.page",
      version: 1,
      token: session.token,
      context: %{organizationId: scope.organization_id, resourceId: account_id}
    }

    page =
      case read(scope, account_id) do
        {:ok, model} ->
          Map.merge(envelope, %{
            status: "ready",
            data: %{model: model, sequence: session.sequence, locked: session.locked}
          })

        _ ->
          Map.put(envelope, :status, "unavailable")
      end

    Phoenix.Component.assign(socket,
      provider_detail_session: session,
      organization_module_page: page
    )
  end

  def prepare(socket, _info, _path),
    do: Phoenix.Component.assign(socket, :provider_detail_session, nil)

  def matches?(socket, %{"id" => @id, "token" => token, "path" => path}) when is_binary(token) do
    case socket.assigns[:provider_detail_session] do
      %{path: ^path, token: ^token, organization_id: org, user_id: user} ->
        path == socket.assigns.host_path and org == socket.assigns.current_scope.organization_id and
          user == socket.assigns.current_scope.user.user_id

      _ ->
        false
    end
  end

  def matches?(_socket, _params), do: false

  def action(socket, "refresh", _input) do
    case read(socket.assigns.current_scope, socket.assigns.provider_detail_session.account_id) do
      {:ok, model} -> {%{status: "ok", data: model}, socket}
      _ -> {%{status: "unknown"}, socket}
    end
  end

  def action(socket, event, input) do
    session = socket.assigns.provider_detail_session

    with {:ok, action} <- Map.fetch(@actions, event),
         true <- valid_input?(input, session) do
      session = %{session | sequence: input["sequence"]}
      socket = Phoenix.Component.assign(socket, :provider_detail_session, session)

      case ProviderAccountOperations.admit(
             socket.assigns.current_scope,
             session.account_id,
             input
           ) do
        :ok ->
          result = execute(socket.assigns.current_scope, action, session.account_id, input)
          session = %{session | locked: result.status == "unknown"}
          {result, Phoenix.Component.assign(socket, :provider_detail_session, session)}

        _ ->
          {%{status: "rejected"}, socket}
      end
    else
      _ -> {%{status: "unknown"}, socket}
    end
  end

  defp valid_input?(input, session) when is_map(input) do
    not session.locked and input["provider_account_id"] == session.account_id and
      is_integer(input["sequence"]) and input["sequence"] == session.sequence + 1 and
      input["sequence"] <= 1_000_000 and map_size(input) <= 10 and
      Enum.all?(input, &valid_field?/1)
  end

  defp valid_input?(_input, _session), do: false

  defp valid_field?({key, value})
       when key in ~w(sequence expected_account_version expected_credential_version expected_grant_version),
       do: is_integer(value) and value > 0

  defp valid_field?({key, value}) when key in ~w(provider_account_id credential_ref grant-id),
    do: is_binary(value) and byte_size(value) in 1..256

  defp valid_field?({"grant", grant}) when is_map(grant),
    do: map_size(grant) <= 5 and Enum.all?(grant, &valid_grant_field?/1)

  defp valid_field?(_field), do: false

  defp valid_grant_field?({key, value}) do
    key in ~w(mission_id allowed_services allowed_stations max_quota grant_reason) and
      is_binary(value) and byte_size(value) <= 8192
  end

  defp execute(scope, action, account_id, input) do
    with {:ok, _} <- ProviderAccountOperations.execute(scope, action, input),
         {:ok, model} <- read(scope, account_id) do
      %{
        status: "ok",
        data: %{
          receiptId: Ecto.UUID.generate(),
          completedAt: DateTime.to_iso8601(DateTime.utc_now()),
          result: %{patch: model}
        }
      }
    else
      _ -> %{status: "unknown"}
    end
  rescue
    _ -> %{status: "unknown"}
  end

  defp read(scope, account_id) do
    ProviderAccountDetail.load(scope, account_id)
  rescue
    _ -> {:error, :unavailable}
  end
end
