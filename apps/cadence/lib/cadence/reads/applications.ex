defmodule Cadence.Reads.Applications do
  @moduledoc "Host-standard read boundary for registered application status projections."

  alias Cadence.Applications.{
    ApplicationDefinition,
    ApplicationInstallation,
    ApplicationInstallations,
    HostContext,
    Registry,
    Status
  }

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Reads.Applications.DerivedTelemetryStatus
  alias Cadence.Reads.Applications.LimitsStatus
  alias Cadence.Reads.Applications.TelemetryDecomStatus

  @providers %{
    "cadence.telemetry_decom.status" => TelemetryDecomStatus,
    "cadence.derived_telemetry.status" => DerivedTelemetryStatus,
    "cadence.limits.status" => LimitsStatus
  }

  @spec validate_providers() ::
          :ok | {:error, :invalid_application_status_provider_registry}
  def validate_providers, do: validate_providers(Registry.all(), @providers)

  @doc false
  @spec validate_providers([ApplicationDefinition.t()], map()) ::
          :ok | {:error, :invalid_application_status_provider_registry}
  def validate_providers(definitions, providers)
      when is_list(definitions) and is_map(providers) do
    required_query_ids =
      definitions
      |> Enum.map(& &1.status_query_id)
      |> Enum.reject(&is_nil/1)

    registered_query_ids = Map.keys(providers)

    if unique?(required_query_ids) and
         same_identities?(required_query_ids, registered_query_ids) and
         Enum.all?(providers, fn {_query_id, provider} ->
           Code.ensure_loaded?(provider) and function_exported?(provider, :load, 2)
         end) do
      :ok
    else
      {:error, :invalid_application_status_provider_registry}
    end
  end

  def validate_providers(_definitions, _providers),
    do: {:error, :invalid_application_status_provider_registry}

  @spec load_status(Scope.t(), ApplicationDefinition.t(), HostContext.t()) ::
          {:ok, Status.t()} | {:error, term()}
  def load_status(
        %Scope{} = current_scope,
        %ApplicationDefinition{status_query_id: query_id} = requested_definition,
        %HostContext{} = host_context
      )
      when is_binary(query_id) do
    with {:ok, definition} <-
           Registry.fetch_available(
             requested_definition.application_key,
             requested_definition.version
           ),
         true <- definition == requested_definition,
         :ok <- authorize_status(current_scope, host_context),
         {:ok, installation} <-
           ApplicationInstallations.fetch_installed(
             current_scope,
             host_context,
             definition.application_key
           ),
         :ok <- ensure_installation_version(installation, definition.version),
         {:ok, provider} <- fetch_provider(query_id) do
      provider.load(current_scope, host_context)
    else
      false -> {:error, :undeclared_application_status_query}
      {:error, reason} -> {:error, reason}
    end
  end

  def load_status(
        %Scope{},
        %ApplicationDefinition{availability: :roadmap},
        %HostContext{}
      ) do
    {:ok, Status.roadmap()}
  end

  def load_status(%Scope{}, %ApplicationDefinition{}, %HostContext{}) do
    {:ok, Status.unavailable()}
  end

  defp fetch_provider(query_id) do
    case Map.fetch(@providers, query_id) do
      {:ok, provider} -> {:ok, provider}
      :error -> {:error, :unknown_application_status_query}
    end
  end

  defp authorize_status(current_scope, host_context) do
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
