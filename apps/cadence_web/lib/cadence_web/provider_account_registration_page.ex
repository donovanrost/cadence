defmodule CadenceWeb.ProviderAccountRegistrationPage do
  @moduledoc "Page-instance admission for the Communications registration contribution."

  alias Cadence.Auth.Policy
  alias Cadence.GroundNetworks.ProviderAccountRegistration

  @id "comms.provider-account-registration"

  def prepare(socket, %{route: "/provider-accounts/new"}, path) do
    scope = socket.assigns.current_scope

    session =
      case socket.assigns[:provider_registration_session] do
        %{path: ^path, organization_id: org, user_id: user} = previous
        when org == scope.organization_id and user == scope.user.user_id ->
          previous

        _ ->
          %{
            path: path,
            organization_id: scope.organization_id,
            user_id: scope.user.user_id,
            token: Ecto.UUID.generate(),
            phase: :editing,
            model: ProviderAccountRegistration.props()
          }
      end

    Phoenix.Component.assign(socket,
      provider_registration_session: session,
      organization_module_page: %{
        id: @id,
        slot: "organization.page",
        version: 1,
        context: %{organizationId: scope.organization_id},
        status: if(session.phase == :editing, do: "ready", else: "unavailable"),
        token: session.token,
        data: session.model
      }
    )
  end

  def prepare(socket, _info, _path),
    do: Phoenix.Component.assign(socket, :provider_registration_session, nil)

  def matches?(socket, %{"id" => @id, "token" => token, "path" => path})
      when is_binary(token) do
    case socket.assigns[:provider_registration_session] do
      %{token: ^token, path: ^path, organization_id: org, user_id: user, phase: :editing} ->
        path == socket.assigns.host_path and
          org == socket.assigns.current_scope.organization_id and
          user == socket.assigns.current_scope.user.user_id

      _ ->
        false
    end
  end

  def matches?(_socket, _input), do: false

  def action(socket, event, input) do
    scope = socket.assigns.current_scope
    session = socket.assigns.provider_registration_session

    with :ok <-
           Policy.authorize(scope, :manage_provider_accounts, %{
             organization_id: scope.organization_id
           }),
         {:ok, values} <- admitted_values(input, session.model) do
      execute(socket, event, values)
    else
      _ -> {%{status: "rejected"}, socket}
    end
  end

  defp admitted_values(%{"provider_account" => values}, model) when is_map(values) do
    fields =
      Map.values(model.form.fields) ++
        Enum.flat_map(model.form.connector.configuration.sections, & &1.fields)

    # Connector switches may introduce different configuration fields. They are
    # normalized by the domain form builder; all input values remain bounded text.
    valid? =
      map_size(values) <= 64 and
        Enum.all?(values, fn {key, value} ->
          is_binary(key) and byte_size(key) <= 128 and is_binary(value) and
            byte_size(value) <= 8192
        end)

    pinned? =
      Enum.all?(model.form.hidden_field_keys, fn key ->
        field = Enum.find(fields, &(&1.key == key))
        field != nil and values[key] == field.value
      end)

    if valid? and pinned?, do: {:ok, values}, else: {:error, :invalid_input}
  end

  defp admitted_values(_input, _model), do: {:error, :invalid_input}

  defp execute(socket, "validate", values) do
    result = completed(%{patch: %{form: ProviderAccountRegistration.form(values)}})
    {result, socket}
  rescue
    _ -> {%{status: "rejected"}, socket}
  end

  defp execute(socket, "save", values) do
    # Consume before invoking an effect. Uncertain/partial completion must not be
    # replayed by a refresh of the same page instance. This is not global exactly-once.
    session = %{socket.assigns.provider_registration_session | phase: :submitted}
    socket = Phoenix.Component.assign(socket, :provider_registration_session, session)
    {register(socket.assigns.current_scope, values), socket}
  end

  defp register(scope, values) do
    case ProviderAccountRegistration.create(scope, values) do
      {:ok, receipt} -> completed(receipt)
      _ -> %{status: "unknown"}
    end
  rescue
    _ -> %{status: "unknown"}
  end

  defp completed(result) do
    %{
      status: "ok",
      data: %{
        receiptId: Ecto.UUID.generate(),
        completedAt: DateTime.to_iso8601(DateTime.utc_now()),
        result: result
      }
    }
  end
end
