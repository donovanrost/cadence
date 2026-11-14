defmodule Cadence.Applications.OrganizationAdminAction do
  @moduledoc "Stable Phoenix-owned action contracts for the organization admin remote."

  alias Cadence.Applications.ActionContractLedger
  alias Cadence.Applications.{ActionFailure, ActionRequest, HostContext}
  alias Cadence.Applications.OrganizationAdminProviders, as: Providers
  alias Cadence.Auth.Scope
  alias Cadence.Notifications.Actions, as: NotificationActions

  @action_contracts [
    %{
      id: "mark_notification_read",
      version: 1,
      surface_id: "notifications_bell",
      effect: :durable,
      host_owned?: false
    }
  ]

  @doc "Returns all action contracts, including surface-local overloads."
  @spec all() :: [map()]
  def all, do: @action_contracts

  @doc "Validates a complete provider-owned surface/action binding ledger."
  @spec validate_bindings([map()]) :: :ok | {:error, atom()}
  def validate_bindings(action_contracts) when is_list(action_contracts) do
    if Enum.all?(action_contracts, &valid_action_contract?/1) do
      identities = Enum.map(action_contracts, &{&1.surface_id, &1.version, &1.id})

      if length(identities) == length(Enum.uniq(identities)),
        do: :ok,
        else: {:error, :duplicate_action_bindings}
    else
      {:error, :invalid_action_contracts}
    end
  end

  def validate_bindings(_action_contracts), do: {:error, :invalid_action_contracts}

  @doc false
  @spec application_key() :: binary()
  def application_key, do: "organization_admin"

  @doc "Executes an authenticated organization, user, or platform-admin action."
  @spec execute(Scope.t(), HostContext.t(), ActionRequest.t()) ::
          {:ok, term()} | {:error, ActionFailure.t() | term()}
  def execute(
        %Scope{} = scope,
        %HostContext{} = host_context,
        %ActionRequest{application_key: "organization_admin", application_version: 1} = request
      ) do
    with :ok <- ensure_surface_binding(request),
         :ok <- ensure_action_context(scope, host_context, request.action_id) do
      execute_action(scope, host_context, request)
    end
  end

  def execute(_scope, _host_context, _request),
    do: {:error, failure("invalid_action", "The organization action request is invalid.")}

  defp execute_action(scope, _host_context, %ActionRequest{
         action_id: "mark_notification_read",
         params: params
       }) do
    with {:ok, id} <- required_param(params, "notification_id"),
         {:ok, _} <-
           NotificationActions.execute(scope, "mark_notification_read", %{
             "notification_id" => id
           }) do
      {:ok, %{patch: Providers.Notifications.bell_props(scope)}}
    end
  end

  defp execute_action(_scope, _host_context, _request),
    do: {:error, failure("unsupported_action", "The organization action is not implemented.")}

  defp ensure_surface_binding(%ActionRequest{} = request),
    do: ActionContractLedger.admit(request, __MODULE__)

  defp ensure_action_context(
         %Scope{organization_id: organization_id},
         %HostContext{placement: :organization, organization_id: organization_id},
         action_id
       )
       when is_binary(organization_id) do
    if action_id in organization_actions(),
      do: :ok,
      else: {:error, :unsupported_application_action_scope}
  end

  defp ensure_action_context(
         %Scope{actor_kind: :user, user: %{user_id: user_id}},
         %HostContext{placement: :user, user_id: user_id},
         action_id
       ) do
    if action_id in user_actions(), do: :ok, else: {:error, :unsupported_application_action_scope}
  end

  defp ensure_action_context(_scope, _host_context, _action_id), do: {:error, :scope_mismatch}

  # L13 moved the provider-account actions to the console; no organization-placed action is left.
  defp organization_actions, do: []

  defp user_actions, do: ["mark_notification_read"]

  defp required_param(params, key) do
    case value(params, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _other -> {:error, failure("invalid_input", "The action input is invalid.")}
    end
  end

  defp value(params, key) when is_map(params) and is_binary(key) do
    Map.get(params, key) || Map.get(params, atom_key(key))
  end

  defp atom_key("notification_id"), do: :notification_id
  defp atom_key(_key), do: nil

  defp failure(code, message), do: %ActionFailure{code: code, message: message}

  @doc "Finds an action by its surface and durable action identity."
  @spec fetch(binary(), binary(), pos_integer()) :: {:ok, map()} | {:error, :unknown_action}
  def fetch(surface_id, action_id, version \\ 1)

  def fetch(surface_id, action_id, version)
      when is_binary(surface_id) and is_binary(action_id) and is_integer(version) do
    case Enum.find(
           @action_contracts,
           &(&1.surface_id == surface_id and &1.id == action_id and &1.version == version)
         ) do
      nil -> {:error, :unknown_action}
      contract -> {:ok, contract}
    end
  end

  def fetch(_surface_id, _action_id, _version), do: {:error, :unknown_action}

  @doc "Whether the action crosses a Phoenix/host-owned flow boundary."
  @spec host_owned?(binary(), binary()) :: boolean()
  def host_owned?(surface_id, action_id) do
    case fetch(surface_id, action_id) do
      {:ok, contract} -> contract.host_owned?
      {:error, :unknown_action} -> false
    end
  end

  @doc false
  @spec validate() :: :ok | {:error, atom()}
  def validate do
    validate_bindings(@action_contracts)
  end

  defp valid_action_contract?(contract) when is_map(contract) do
    id = Map.get(contract, :id)
    surface_id = Map.get(contract, :surface_id)
    version = Map.get(contract, :version)
    effect = Map.get(contract, :effect)
    host_owned? = Map.get(contract, :host_owned?)

    is_binary(id) and id != "" and is_binary(surface_id) and surface_id != "" and
      is_integer(version) and version > 0 and effect in [:none, :durable, :external] and
      is_boolean(host_owned?)
  end

  defp valid_action_contract?(_contract), do: false
end
