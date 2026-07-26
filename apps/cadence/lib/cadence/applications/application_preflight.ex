defmodule Cadence.Applications.ApplicationPreflight do
  @moduledoc """
  Host-mediated activation preflight for registered product applications.

  The host evaluates application-installation dependencies and invokes only a
  compiled domain provider for resource and configuration checks. It does not
  acquire domain persistence or validation ownership.
  """

  alias Cadence.Applications.{
    ApplicationDefinition,
    ApplicationDependency,
    ApplicationInstallation,
    ApplicationInstallations,
    HostContext,
    PreflightCheck,
    PreflightReport,
    Registry
  }

  alias Cadence.Applications.ApplicationPreflights.TelemetryDecom
  alias Cadence.Auth.{Policy, Scope}

  @providers %{
    "cadence.telemetry_decom.activation_preflight" => TelemetryDecom
  }

  @spec validate_providers() ::
          :ok | {:error, :invalid_application_preflight_provider_registry}
  def validate_providers, do: validate_providers(Registry.all(), @providers)

  @doc false
  @spec validate_providers([ApplicationDefinition.t()], map()) ::
          :ok | {:error, :invalid_application_preflight_provider_registry}
  def validate_providers(definitions, providers)
      when is_list(definitions) and is_map(providers) do
    required_query_ids =
      definitions
      |> Enum.map(& &1.preflight_query_id)
      |> Enum.reject(&is_nil/1)

    registered_query_ids = Map.keys(providers)

    if unique?(required_query_ids) and
         same_identities?(required_query_ids, registered_query_ids) and
         Enum.all?(providers, fn {_query_id, provider} ->
           Code.ensure_loaded?(provider) and function_exported?(provider, :checks, 3)
         end) do
      :ok
    else
      {:error, :invalid_application_preflight_provider_registry}
    end
  end

  def validate_providers(_definitions, _providers),
    do: {:error, :invalid_application_preflight_provider_registry}

  @spec load(Scope.t(), HostContext.t(), ApplicationDefinition.t()) ::
          {:ok, PreflightReport.t()} | {:error, term()}
  def load(
        %Scope{} = current_scope,
        %HostContext{} = host_context,
        %ApplicationDefinition{} = requested_definition
      ) do
    with {:ok, definition} <-
           Registry.fetch_available(
             requested_definition.application_key,
             requested_definition.version
           ),
         true <- definition == requested_definition,
         :ok <- authorize(current_scope, host_context),
         {:ok, installation} <-
           ApplicationInstallations.fetch_installed(
             current_scope,
             host_context,
             definition.application_key
           ),
         :ok <- ensure_installation_version(installation, definition.version) do
      build_report(current_scope, host_context, definition)
    else
      false -> {:error, :undeclared_application_preflight}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec ensure_ready(Scope.t(), HostContext.t(), ApplicationDefinition.t()) ::
          :ok | {:error, term()}
  def ensure_ready(
        %Scope{} = current_scope,
        %HostContext{} = host_context,
        %ApplicationDefinition{} = definition
      ) do
    with {:ok, report} <- load(current_scope, host_context, definition),
         true <- PreflightReport.ready?(report) do
      :ok
    else
      false -> {:error, {:application_preflight_blocked, definition.application_key}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_report(current_scope, host_context, definition) do
    with {:ok, dependency_checks} <-
           evaluate_dependencies(current_scope, host_context, definition.dependencies),
         {:ok, provider_checks} <- provider_checks(current_scope, host_context, definition) do
      {:ok, PreflightReport.new(definition, dependency_checks ++ provider_checks)}
    end
  end

  @doc false
  @spec evaluate_dependencies(Scope.t(), HostContext.t(), [ApplicationDependency.t()]) ::
          {:ok, [PreflightCheck.t()]}
  def evaluate_dependencies(current_scope, host_context, dependencies) do
    checks =
      Enum.map(dependencies, fn dependency ->
        dependency_check(current_scope, host_context, dependency)
      end)

    {:ok, checks}
  end

  defp dependency_check(
         current_scope,
         host_context,
         %ApplicationDependency{} = dependency
       ) do
    target_context = dependency_host_context(host_context, dependency.scope)
    unsatisfied_state = if(dependency.required, do: :blocked, else: :attention)
    label = dependency_label(dependency.application_key)

    case ApplicationInstallations.fetch_installed(
           current_scope,
           target_context,
           dependency.application_key
         ) do
      {:ok, %ApplicationInstallation{application_version: version}}
      when version >= dependency.minimum_version ->
        dependency_check(
          dependency,
          :ready,
          "#{label} installed",
          "The required application installation satisfies the declared minimum version.",
          "v#{version}"
        )

      {:ok, %ApplicationInstallation{application_version: version}} ->
        dependency_check(
          dependency,
          unsatisfied_state,
          "#{label} upgrade required",
          "Version #{dependency.minimum_version} or newer is required before activation.",
          "v#{version}"
        )

      {:error, reason}
      when reason in [
             :application_not_installed,
             :application_installation_disabled,
             :application_installation_uninstalled
           ] ->
        dependency_check(
          dependency,
          unsatisfied_state,
          "#{label} unavailable",
          dependency_missing_detail(reason, dependency),
          nil
        )

      {:error, _reason} ->
        dependency_check(
          dependency,
          unsatisfied_state,
          "#{label} unavailable",
          "Cadence could not verify the declared application dependency.",
          nil
        )
    end
  end

  defp dependency_check(dependency, state, title, detail, value) do
    %PreflightCheck{
      id: "dependency-#{dependency.scope}-#{dependency.application_key}",
      category: :dependency,
      state: state,
      title: title,
      detail: dependency.description || detail,
      value: value
    }
  end

  defp dependency_host_context(host_context, :same_host), do: host_context

  defp dependency_host_context(%HostContext{mission_id: mission_id}, :mission),
    do: HostContext.mission(mission_id)

  defp dependency_label(application_key) do
    case Registry.fetch(application_key) do
      {:ok, definition} -> definition.display_name
      {:error, _reason} -> application_key
    end
  end

  defp dependency_missing_detail(:application_not_installed, dependency) do
    "Install #{dependency.application_key} at the declared #{dependency.scope} scope."
  end

  defp dependency_missing_detail(:application_installation_disabled, dependency) do
    "Enable #{dependency.application_key} at the declared #{dependency.scope} scope."
  end

  defp dependency_missing_detail(:application_installation_uninstalled, dependency) do
    "Reinstall #{dependency.application_key} at the declared #{dependency.scope} scope."
  end

  defp provider_checks(
         _current_scope,
         _host_context,
         %ApplicationDefinition{preflight_query_id: nil}
       ),
       do: {:ok, []}

  defp provider_checks(current_scope, host_context, %ApplicationDefinition{} = definition) do
    case Map.fetch(@providers, definition.preflight_query_id) do
      {:ok, provider} -> provider.checks(current_scope, host_context, definition)
      :error -> {:error, :unknown_application_preflight_query}
    end
  end

  defp authorize(current_scope, host_context) do
    Policy.authorize(current_scope, :operate_mission, %{
      organization_id: current_scope.organization_id,
      mission_id: host_context.mission_id
    })
  end

  defp ensure_installation_version(
         %ApplicationInstallation{application_version: version},
         version
       ),
       do: :ok

  defp ensure_installation_version(%ApplicationInstallation{}, _requested_version),
    do: {:error, :application_installation_version_mismatch}

  defp same_identities?(left, right),
    do: MapSet.equal?(MapSet.new(left), MapSet.new(right))

  defp unique?(identities), do: length(identities) == length(Enum.uniq(identities))
end
