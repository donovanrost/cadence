defmodule Cadence.Applications.Comms.ActionProvider do
  @moduledoc "Typed action adapter for mission Comms provider operations."

  @behaviour Cadence.Applications.ActionProvider

  alias Cadence.Applications.ActionContractLedger
  alias Cadence.Applications.{ActionRequest, HostContext}
  alias Cadence.Auth.Scope

  alias Cadence.Control.Providers, as: ControlProviders
  alias Cadence.GroundNetworks.{MissionProvider, MissionProviderRegistration}
  alias Cadence.Management.CommunicationsSetup
  alias Cadence.Management.Providers

  @application_key "comms"
  @form_surfaces ~w(transport_new routing_new ground_station_new ground_station_edit)
  @surface_action_bindings [
    {"provider_new", 1, "create_provider"},
    {"provider_show", 1, "validate_provider"},
    {"provider_show", 1, "sync_provider"},
    {"provider_show", 1, "archive_provider"},
    {"transport_new", 1, "validate"},
    {"transport_new", 1, "save"},
    {"routing_new", 1, "validate"},
    {"routing_new", 1, "save"},
    {"ground_station_new", 1, "validate"},
    {"ground_station_new", 1, "save"},
    {"ground_station_edit", 1, "validate"},
    {"ground_station_edit", 1, "save"}
  ]

  @impl true
  def application_key, do: @application_key

  @doc "Returns the frozen provider-owned surface/action binding ledger."
  @spec surface_action_bindings() :: [{binary(), pos_integer(), binary()}]
  def surface_action_bindings, do: @surface_action_bindings

  @doc "Validates that every binding row is unique and well formed."
  @spec validate_bindings(list()) :: :ok | {:error, atom()}
  def validate_bindings(bindings) when is_list(bindings) do
    valid? =
      Enum.all?(bindings, fn
        {surface_id, surface_version, action_id} ->
          is_binary(surface_id) and surface_id != "" and
            is_integer(surface_version) and surface_version > 0 and
            is_binary(action_id) and action_id != ""

        _other ->
          false
      end)

    cond do
      not valid? -> {:error, :invalid_action_bindings}
      length(bindings) != length(Enum.uniq(bindings)) -> {:error, :duplicate_action_bindings}
      true -> :ok
    end
  end

  def validate_bindings(_bindings), do: {:error, :invalid_action_bindings}

  defp execute_action(
         %Scope{} = scope,
         %HostContext{placement: :mission, mission_id: mission_id},
         %ActionRequest{
           application_key: @application_key,
           application_version: 1,
           action_id: "validate",
           surface_id: surface_id,
           surface_version: 1,
           params: params
         }
       )
       when surface_id in @form_surfaces and is_map(params) do
    CommunicationsSetup.execute(scope, mission_id, surface_id, "validate", params)
  end

  defp execute_action(
         %Scope{} = scope,
         %HostContext{placement: :mission, mission_id: mission_id},
         %ActionRequest{
           application_key: @application_key,
           application_version: 1,
           action_id: "save",
           surface_id: surface_id,
           surface_version: 1,
           params: params
         }
       )
       when surface_id in @form_surfaces and is_map(params) do
    CommunicationsSetup.execute(scope, mission_id, surface_id, "save", params)
  end

  defp execute_action(
         %Scope{} = scope,
         %HostContext{placement: :mission, mission_id: mission_id},
         %ActionRequest{
           application_key: @application_key,
           application_version: 1,
           action_id: action_id,
           params: params
         }
       )
       when action_id in ["validate_provider", "sync_provider", "archive_provider"] do
    with {:ok, provider_id} <- required_id(params, "provider_id") do
      case action_id do
        "validate_provider" -> ControlProviders.validate_current(scope, mission_id, provider_id)
        "sync_provider" -> ControlProviders.sync_current(scope, mission_id, provider_id)
        "archive_provider" -> Providers.archive_provider(scope, mission_id, provider_id)
      end
    end
  end

  defp execute_action(
         %Scope{} = scope,
         %HostContext{placement: :mission, mission_id: mission_id},
         %ActionRequest{
           application_key: @application_key,
           application_version: 1,
           action_id: "create_provider",
           params: params
         }
       ) do
    MissionProviderRegistration.create(scope, mission_id, Map.get(params, "provider", params))
  end

  defp execute_action(%Scope{}, %HostContext{}, %ActionRequest{}),
    do: {:error, :application_action_scope_required}

  @impl true
  def execute(%Scope{} = scope, %HostContext{} = host_context, %ActionRequest{} = request) do
    with :ok <- ActionContractLedger.admit(request, __MODULE__) do
      execute_action(scope, host_context, request)
    end
  end

  def execute(_scope, _host_context, _request),
    do: {:error, :unsupported_application_action}

  @impl true
  def result(%MissionProvider{} = provider) do
    %{
      "provider_id" => provider.provider_id,
      "version" => provider.version,
      "display_name" => provider.display_name
    }
  end

  def result(value) when is_map(value), do: value
  def result(value), do: value

  defp required_id(params, key) when is_map(params) do
    case Map.get(params, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _invalid -> {:error, {:missing_action_parameter, key}}
    end
  end

  defp required_id(_params, key), do: {:error, {:missing_action_parameter, key}}
end
