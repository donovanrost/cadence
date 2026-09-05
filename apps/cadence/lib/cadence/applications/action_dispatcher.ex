defmodule Cadence.Applications.ActionDispatcher do
  @moduledoc """
  Host-owned authorization and dispatch boundary for typed application actions.

  v1 dispatches compiled first-party providers and requires an exact active
  installation. Application-owned configuration remains in its owning context;
  the host records only the typed version reference returned by the provider.
  """

  alias Cadence.Applications.{
    ActionDefinition,
    ActionContractLedger,
    ActionFailure,
    ActionRequest,
    ApplicationDefinition,
    ApplicationInstallation,
    ApplicationInstallations,
    ApplicationPreflight,
    ConfigurationReference,
    HostContext,
    LifecycleContract,
    Registry
  }

  alias Cadence.Applications.ActionProviderRegistry
  alias Cadence.Auth.{Policy, Scope}

  @spec validate_providers() ::
          :ok | {:error, :invalid_application_action_provider_registry}
  def validate_providers do
    with :ok <- validate_providers(Registry.all(), ActionProviderRegistry.providers()),
         :ok <- ActionContractLedger.validate() do
      :ok
    else
      {:error, :invalid_application_action_contract_ledger} ->
        {:error, :invalid_application_action_provider_registry}

      {:error, _reason} ->
        {:error, :invalid_application_action_provider_registry}
    end
  end

  @doc false
  @spec validate_providers([ApplicationDefinition.t()], map()) ::
          :ok | {:error, :invalid_application_action_provider_registry}
  def validate_providers(definitions, providers)
      when is_list(definitions) and is_map(providers) do
    required_keys =
      definitions
      |> Enum.filter(fn definition ->
        definition.actions != [] or definition.lifecycle_contract.actions != []
      end)
      |> Enum.map(& &1.application_key)

    registered_keys = Map.keys(providers)

    if unique?(required_keys) and same_identities?(required_keys, registered_keys) and
         ActionProviderRegistry.validate(providers) == :ok and
         Enum.all?(providers, fn {_application_key, provider} ->
           Code.ensure_loaded?(provider) and function_exported?(provider, :execute, 3)
         end) do
      :ok
    else
      {:error, :invalid_application_action_provider_registry}
    end
  end

  def validate_providers(_definitions, _providers),
    do: {:error, :invalid_application_action_provider_registry}

  @spec dispatch(Scope.t(), HostContext.t(), ActionRequest.t()) ::
          {:ok, term()} | {:error, term()}
  def dispatch(
        %Scope{} = current_scope,
        %HostContext{placement: placement} = host_context,
        %ActionRequest{} = request
      )
      when placement in [:organization, :user, :admin] do
    dispatch(current_scope, host_context, request, ActionProviderRegistry.providers())
  end

  def dispatch(
        %Scope{organization_id: organization_id} = current_scope,
        %HostContext{} = host_context,
        %ActionRequest{} = request
      )
      when is_binary(organization_id) do
    dispatch(current_scope, host_context, request, ActionProviderRegistry.providers())
  end

  def dispatch(%Scope{}, %HostContext{}, %ActionRequest{}),
    do: {:error, :application_action_scope_required}

  @doc "Runs every action authorization and preflight check without executing the provider."
  @spec authorize(Scope.t(), HostContext.t(), ActionRequest.t()) :: :ok | {:error, term()}
  def authorize(
        %Scope{} = current_scope,
        %HostContext{placement: placement} = host_context,
        %ActionRequest{} = request
      )
      when placement in [:organization, :user, :admin] do
    authorize(current_scope, host_context, request, ActionProviderRegistry.providers())
  end

  def authorize(
        %Scope{organization_id: organization_id} = current_scope,
        %HostContext{} = host_context,
        %ActionRequest{} = request
      )
      when is_binary(organization_id) do
    authorize(current_scope, host_context, request, ActionProviderRegistry.providers())
  end

  def authorize(%Scope{}, %HostContext{}, %ActionRequest{}),
    do: {:error, :application_action_scope_required}

  @doc false
  @spec authorize(Scope.t(), HostContext.t(), ActionRequest.t(), map()) ::
          :ok | {:error, term()}
  def authorize(
        %Scope{} = current_scope,
        %HostContext{placement: placement} = host_context,
        %ActionRequest{} = request,
        registered_providers
      )
      when placement in [:organization, :user, :admin] and is_map(registered_providers) do
    case authorization_context(current_scope, host_context, request, registered_providers) do
      {:ok, _context} -> :ok
      {:error, _reason} = error -> error
    end
  end

  def authorize(
        %Scope{organization_id: organization_id} = current_scope,
        %HostContext{} = host_context,
        %ActionRequest{} = request,
        registered_providers
      )
      when is_binary(organization_id) and is_map(registered_providers) do
    case authorization_context(current_scope, host_context, request, registered_providers) do
      {:ok, _context} -> :ok
      {:error, _reason} = error -> error
    end
  end

  def authorize(%Scope{}, %HostContext{}, %ActionRequest{}, _registered_providers),
    do: {:error, :application_action_scope_required}

  @doc false
  @spec dispatch(Scope.t(), HostContext.t(), ActionRequest.t(), map()) ::
          {:ok, term()} | {:error, term()}
  def dispatch(
        %Scope{} = current_scope,
        %HostContext{placement: placement} = host_context,
        %ActionRequest{} = request,
        registered_providers
      )
      when placement in [:organization, :user, :admin] and is_map(registered_providers) do
    with {:ok, %{provider: provider, installation: installation}} <-
           authorization_context(current_scope, host_context, request, registered_providers),
         {:ok, result} <- invoke_execute(provider, current_scope, host_context, request),
         {:ok, _installation} <-
           record_installation_outcome(
             current_scope,
             host_context,
             request,
             provider,
             result,
             installation
           ) do
      {:ok, result}
    end
  end

  def dispatch(
        %Scope{organization_id: organization_id} = current_scope,
        %HostContext{} = host_context,
        %ActionRequest{} = request,
        registered_providers
      )
      when is_binary(organization_id) and is_map(registered_providers) do
    with {:ok, %{provider: provider, installation: installation}} <-
           authorization_context(current_scope, host_context, request, registered_providers),
         {:ok, result} <- invoke_execute(provider, current_scope, host_context, request),
         {:ok, _installation} <-
           record_installation_outcome(
             current_scope,
             host_context,
             request,
             provider,
             result,
             installation
           ) do
      {:ok, result}
    end
  end

  def dispatch(%Scope{}, %HostContext{}, %ActionRequest{}, _registered_providers),
    do: {:error, :application_action_scope_required}

  defp authorization_context(
         current_scope,
         host_context,
         request,
         registered_providers
       ) do
    with {:ok, definition} <-
           Registry.fetch_available(request.application_key, request.application_version),
         :ok <- ensure_host_scope(definition, host_context),
         {:ok, required_permission} <- declared_action_permission(definition, request.action_id),
         {:ok, provider} <- fetch_provider(request.application_key, registered_providers),
         :ok <- authorize_action(current_scope, host_context, required_permission),
         {:ok, installation} <-
           maybe_fetch_installation(
             current_scope,
             host_context,
             request.application_key
           ),
         :ok <- ensure_installation_version(installation, request.application_version),
         :ok <- ensure_expected_configuration_version(installation, request),
         :ok <-
           ensure_action_preflight(current_scope, host_context, definition, request.action_id) do
      {:ok, %{provider: provider, installation: installation}}
    end
  end

  defp ensure_host_scope(
         %ApplicationDefinition{installable_scopes: scopes},
         %HostContext{placement: placement}
       ) do
    if placement in scopes, do: :ok, else: {:error, :unsupported_application_host_context}
  end

  defp declared_action_permission(%ApplicationDefinition{} = definition, action_id) do
    case Enum.find(definition.actions, &(&1.action_id == action_id)) do
      %ActionDefinition{} = action ->
        if action.scope in definition.installable_scopes,
          do: {:ok, action.required_permission},
          else: {:error, :unsupported_application_action_scope}

      nil ->
        lifecycle_action_permission(definition.lifecycle_contract, action_id)
    end
  end

  defp lifecycle_action_permission(%LifecycleContract{} = contract, action_id) do
    case LifecycleContract.fetch_action(contract, action_id) do
      {:ok, action} -> {:ok, action.required_permission}
      {:error, reason} -> {:error, reason}
    end
  end

  defp lifecycle_action_permission(_contract, _action_id),
    do: {:error, :undeclared_application_action}

  defp authorize_action(current_scope, host_context, required_permission) do
    params = %{
      organization_id: current_scope.organization_id,
      mission_id: host_context.mission_id
    }

    case {host_context.placement, required_permission} do
      {:organization, "operate_mission"} ->
        Policy.authorize(current_scope, :operate_organization, %{
          organization_id: current_scope.organization_id
        })

      {_placement, "operate_mission"} ->
        Policy.authorize(current_scope, :operate_mission, params)

      {_placement, "request_activation"} ->
        Policy.authorize(current_scope, :request_activation, params)

      {_placement, "manage_provider_accounts"} ->
        Policy.authorize(current_scope, :manage_provider_accounts, %{
          organization_id: organization_id_for(host_context, current_scope)
        })

      {_placement, "manage_service_identities"} ->
        Policy.authorize(current_scope, :manage_service_identities, %{
          organization_id: organization_id_for(host_context, current_scope)
        })

      {_placement, "read_notifications"} ->
        authorize_user_context(current_scope, host_context)

      {_placement, "accept_invitation"} ->
        authorize_user_context(current_scope, host_context)

      {_placement, "view_runtime"} ->
        authorize_admin_context(current_scope, host_context)

      {_placement, "manage_organizations"} ->
        authorize_admin_context(current_scope, host_context)

      {_placement, "dismiss_service_token"} ->
        authorize_admin_context(current_scope, host_context)

      {_placement, "open_organization"} ->
        authorize_admin_context(current_scope, host_context)

      _other ->
        {:error, :unsupported_application_permission}
    end
  end

  defp organization_id_for(
         %HostContext{organization_id: organization_id},
         %Scope{organization_id: scope_organization_id}
       ),
       do: organization_id || scope_organization_id

  defp authorize_user_context(
         %Scope{actor_kind: :user, user: %{user_id: user_id}},
         %HostContext{placement: :user, user_id: user_id}
       ),
       do: :ok

  defp authorize_user_context(%Scope{}, %HostContext{}), do: {:error, :scope_mismatch}

  defp authorize_admin_context(%Scope{} = scope, %HostContext{placement: :admin}) do
    if Scope.admin_mode?(scope), do: :ok, else: {:error, :forbidden}
  end

  defp authorize_admin_context(%Scope{}, %HostContext{}), do: {:error, :scope_mismatch}

  defp maybe_fetch_installation(
         current_scope,
         %HostContext{placement: placement} = host_context,
         application_key
       ) do
    if installation_exempt?(application_key, placement) do
      {:ok, nil}
    else
      ApplicationInstallations.fetch_installed(current_scope, host_context, application_key)
    end
  end

  @doc false
  @spec installation_exempt?(binary(), HostContext.placement()) :: boolean()
  def installation_exempt?("mission_catalog", :organization), do: true

  def installation_exempt?("organization_admin", placement)
      when placement in [:organization, :user, :admin],
      do: true

  def installation_exempt?(_application_key, _placement), do: false

  defp fetch_provider(application_key, registered_providers) do
    case ActionProviderRegistry.fetch(application_key, registered_providers) do
      {:ok, provider} -> {:ok, provider}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec result(binary(), term()) :: term()
  def result(application_key, value) when is_binary(application_key) do
    case ActionProviderRegistry.fetch(application_key) do
      {:ok, provider} ->
        if function_exported?(provider, :result, 1), do: provider.result(value), else: value

      _other ->
        value
    end
  end

  def result(_application_key, value), do: value

  defp invoke_execute(provider, current_scope, host_context, request) do
    case safe_apply(provider, :execute, [current_scope, host_context, request]) do
      {:ok, {:ok, result}} -> {:ok, result}
      {:ok, {:error, reason}} -> {:error, reason}
      {:ok, _malformed} -> {:error, action_provider_failure()}
      {:error, :provider_exception} -> {:error, action_provider_failure()}
    end
  end

  defp same_identities?(left, right),
    do: MapSet.equal?(MapSet.new(left), MapSet.new(right))

  defp unique?(identities), do: length(identities) == length(Enum.uniq(identities))

  defp ensure_installation_version(
         %ApplicationInstallation{application_version: version},
         version
       ),
       do: :ok

  defp ensure_installation_version(nil, _requested_version), do: :ok

  defp ensure_installation_version(%ApplicationInstallation{}, _requested_version),
    do: {:error, :application_installation_version_mismatch}

  defp ensure_expected_configuration_version(
         nil,
         %ActionRequest{expected_configuration_version: nil}
       ),
       do: :ok

  defp ensure_expected_configuration_version(
         %ApplicationInstallation{},
         %ActionRequest{expected_configuration_version: nil}
       ),
       do: :ok

  defp ensure_expected_configuration_version(
         %ApplicationInstallation{
           configuration_ref: %ConfigurationReference{version: version}
         },
         %ActionRequest{expected_configuration_version: version}
       ),
       do: :ok

  defp ensure_expected_configuration_version(
         %ApplicationInstallation{configuration_ref: configuration_ref},
         %ActionRequest{expected_configuration_version: expected_version}
       ) do
    current_version = configuration_ref && configuration_ref.version
    {:error, {:application_configuration_version_conflict, expected_version, current_version}}
  end

  defp ensure_expected_configuration_version(
         nil,
         %ActionRequest{expected_configuration_version: expected_version}
       ),
       do: {:error, {:application_configuration_version_conflict, expected_version, nil}}

  defp ensure_action_preflight(
         current_scope,
         host_context,
         definition,
         "request_activation"
       ) do
    ApplicationPreflight.ensure_ready(current_scope, host_context, definition)
  end

  defp ensure_action_preflight(_current_scope, _host_context, _definition, _action_id), do: :ok

  defp record_installation_outcome(
         current_scope,
         host_context,
         %ActionRequest{action_id: "disable", application_key: application_key},
         provider,
         _result,
         installation
       ) do
    if lifecycle_handled_by_provider?(provider),
      do: {:ok, installation},
      else: ApplicationInstallations.disable(current_scope, host_context, application_key)
  end

  defp record_installation_outcome(
         current_scope,
         host_context,
         %ActionRequest{} = request,
         provider,
         result,
         installation
       ) do
    if lifecycle_handled_by_provider?(provider) and request.action_id in ["install", "uninstall"],
      do: {:ok, installation},
      else:
        record_configuration_outcome(
          current_scope,
          host_context,
          request,
          provider,
          result,
          installation
        )
  end

  defp record_configuration_outcome(
         current_scope,
         host_context,
         %ActionRequest{application_key: application_key} = request,
         provider,
         result,
         installation
       ) do
    if function_exported?(provider, :configuration_reference, 2) do
      case safe_apply(provider, :configuration_reference, [request, result]) do
        {:ok, %ConfigurationReference{} = configuration_ref} ->
          ApplicationInstallations.put_configuration_reference(
            current_scope,
            host_context,
            application_key,
            configuration_ref
          )

        {:ok, nil} ->
          {:ok, installation}

        {:ok, _malformed} ->
          {:error, action_provider_failure()}

        {:error, :provider_exception} ->
          {:error, action_provider_failure()}
      end
    else
      {:ok, installation}
    end
  end

  defp lifecycle_handled_by_provider?(provider) do
    function_exported?(provider, :handles_lifecycle_actions?, 0) and
      provider.handles_lifecycle_actions?()
  end

  defp action_provider_failure do
    %ActionFailure{
      code: "application_action_failed",
      message: "The application could not complete this action."
    }
  end

  defp safe_apply(module, function, arguments) do
    {:ok, apply(module, function, arguments)}
  rescue
    _exception -> {:error, :provider_exception}
  catch
    _kind, _value -> {:error, :provider_exception}
  end
end
