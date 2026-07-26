defmodule Cadence.Applications.ActionDispatcher do
  @moduledoc """
  Host-owned authorization and dispatch boundary for typed application actions.

  v1 dispatches compiled first-party providers and requires an exact active
  installation. Application-owned configuration remains in its owning context;
  the host records only the typed version reference returned by the provider.
  """

  alias Cadence.Applications.{
    ActionDefinition,
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

  alias Cadence.Applications.DerivedTelemetry.ActionProvider, as: DerivedTelemetryActionProvider
  alias Cadence.Applications.Limits.ActionProvider, as: LimitsActionProvider
  alias Cadence.Applications.TelemetryDecom.ActionProvider, as: TelemetryDecomActionProvider
  alias Cadence.Auth.{Policy, Scope}

  @providers %{
    "telemetry_decom" => TelemetryDecomActionProvider,
    "derived_telemetry" => DerivedTelemetryActionProvider,
    "limits" => LimitsActionProvider
  }

  @spec validate_providers() ::
          :ok | {:error, :invalid_application_action_provider_registry}
  def validate_providers, do: validate_providers(Registry.all(), @providers)

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
        %Scope{organization_id: organization_id} = current_scope,
        %HostContext{} = host_context,
        %ActionRequest{} = request
      )
      when is_binary(organization_id) do
    with {:ok, definition} <-
           Registry.fetch_available(request.application_key, request.application_version),
         :ok <- ensure_host_scope(definition, host_context),
         {:ok, required_permission} <- declared_action_permission(definition, request.action_id),
         {:ok, provider} <- fetch_provider(request.application_key),
         :ok <- authorize_action(current_scope, host_context, required_permission),
         {:ok, installation} <-
           ApplicationInstallations.fetch_installed(
             current_scope,
             host_context,
             request.application_key
           ),
         :ok <- ensure_installation_version(installation, request.application_version),
         :ok <- ensure_expected_configuration_version(installation, request),
         :ok <-
           ensure_action_preflight(current_scope, host_context, definition, request.action_id),
         {:ok, result} <- provider.execute(current_scope, host_context, request),
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

  def dispatch(%Scope{}, %HostContext{}, %ActionRequest{}),
    do: {:error, :application_action_scope_required}

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

    case required_permission do
      "operate_mission" -> Policy.authorize(current_scope, :operate_mission, params)
      "request_activation" -> Policy.authorize(current_scope, :request_activation, params)
      _other -> {:error, :unsupported_application_permission}
    end
  end

  defp fetch_provider(application_key) do
    case Map.fetch(@providers, application_key) do
      {:ok, provider} -> {:ok, provider}
      :error -> {:error, :unknown_application_action_provider}
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

  defp ensure_installation_version(%ApplicationInstallation{}, _requested_version),
    do: {:error, :application_installation_version_mismatch}

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
         _provider,
         _result,
         _installation
       ) do
    ApplicationInstallations.disable(current_scope, host_context, application_key)
  end

  defp record_installation_outcome(
         current_scope,
         host_context,
         %ActionRequest{application_key: application_key} = request,
         provider,
         result,
         installation
       ) do
    if function_exported?(provider, :configuration_reference, 2) do
      case provider.configuration_reference(request, result) do
        %ConfigurationReference{} = configuration_ref ->
          ApplicationInstallations.put_configuration_reference(
            current_scope,
            host_context,
            application_key,
            configuration_ref
          )

        nil ->
          {:ok, installation}
      end
    else
      {:ok, installation}
    end
  end
end
