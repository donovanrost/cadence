defmodule Cadence.Applications.Spacecraft.ActionProvider do
  @moduledoc "Application-owned action adapter for Spacecraft identity and profile surfaces."

  @behaviour Cadence.Applications.ActionProvider

  alias Cadence.Applications.ActionContractLedger
  alias Cadence.Applications.{ActionDispatcher, ActionFailure, ActionRequest, HostContext}
  alias Cadence.Applications.TelemetryDecom.ActionProvider, as: DecomActions
  alias Cadence.Applications.TelemetryDecom.Config
  alias Cadence.Auth.Scope
  alias Cadence.Spacecraft, as: SpacecraftAsset
  alias Cadence.Spacecraft.{Identity, ProfileCreation}
  alias Cadence.SpacecraftType, as: SpacecraftProfile

  @surface_action_bindings [
    {"new", 1, "validate"},
    {"new", 1, "save"},
    {"profile_new", 1, "validate"},
    {"profile_new", 1, "save"},
    {"edit", 1, "validate"},
    {"edit", 1, "save"},
    {"applications", 1, "install"},
    {"applications", 1, "disable"},
    {"applications", 1, "uninstall"},
    {"telemetry_decom", 1, "save_configuration"},
    {"telemetry_decom", 1, "request_activation"},
    {"telemetry_decom", 1, "disable"}
  ]

  @impl true
  def application_key, do: "spacecraft"

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

  @impl true
  def execute(%Scope{} = scope, %HostContext{} = host_context, %ActionRequest{} = request) do
    with :ok <- ensure_surface_binding(request) do
      execute_action(scope, host_context, request)
    end
  end

  defp execute_action(
         scope,
         %HostContext{placement: :mission, mission_id: mission_id},
         %ActionRequest{surface_id: "new", action_id: event, params: params}
       )
       when event in ["validate", "save"] do
    identity_result(Identity.action(scope, mission_id, nil, event, params))
  end

  defp execute_action(
         scope,
         %HostContext{
           placement: :spacecraft,
           mission_id: mission_id,
           spacecraft_id: spacecraft_id
         },
         %ActionRequest{surface_id: "edit", action_id: event, params: params}
       )
       when event in ["validate", "save"] do
    identity_result(Identity.action(scope, mission_id, spacecraft_id, event, params))
  end

  defp execute_action(
         scope,
         %HostContext{placement: :mission, mission_id: mission_id},
         %ActionRequest{surface_id: "profile_new", action_id: event, params: params}
       )
       when event in ["validate", "save"] do
    identity_result(ProfileCreation.action(scope, mission_id, event, params))
  end

  defp execute_action(
         %Scope{} = scope,
         %HostContext{placement: :spacecraft} = host,
         %ActionRequest{surface_id: "telemetry_decom", action_id: action, params: params} =
           request
       )
       when action in ["save_configuration", "request_activation", "disable"] do
    ActionDispatcher.dispatch(scope, host, %ActionRequest{
      request
      | application_key: "telemetry_decom",
        surface_id: "manage",
        params: nested_or_self(params, "telemetry_decom")
    })
  end

  defp execute_action(%Scope{}, %HostContext{}, %ActionRequest{
         action_id: "disable",
         params: params
       }) do
    case Map.get(params, "key") || Map.get(params, :key) do
      key when is_binary(key) and key != "" ->
        {:error, {:local_application_lifecycle_boundary, key}}

      _other ->
        {:error, :local_application_lifecycle_boundary}
    end
  end

  defp execute_action(%Scope{}, %HostContext{}, %ActionRequest{action_id: action_id})
       when action_id in ["install", "uninstall"],
       do: {:error, :local_application_lifecycle_boundary}

  defp execute_action(%Scope{}, %HostContext{}, %ActionRequest{}),
    do: {:error, :application_action_scope_required}

  defp ensure_surface_binding(%ActionRequest{} = request),
    do: ActionContractLedger.admit(request, __MODULE__)

  @impl true
  def result(%SpacecraftAsset{} = spacecraft),
    do: %{"spacecraftId" => spacecraft.spacecraft_id, "displayName" => spacecraft.display_name}

  def result(%SpacecraftProfile{} = profile),
    do: %{"profileId" => profile.spacecraft_type_id, "version" => profile.version}

  def result(%Config{} = config), do: DecomActions.result(config)
  def result(%{config: %Config{}} = result), do: DecomActions.result(result)

  def result(value) when is_map(value), do: value
  def result(_value), do: nil

  defp nested(params, key) when is_map(params), do: Map.get(params, key, %{})
  defp nested(_params, _key), do: %{}

  defp nested_or_self(params, key) do
    case nested(params, key) do
      %{} = value when map_size(value) > 0 -> value
      _other -> params
    end
  end

  defp identity_result({:error, errors}) when is_map(errors) and not is_struct(errors) do
    {field, messages} = errors |> Enum.sort() |> List.first()
    {:error, %ActionFailure{code: "invalid_field", field: field, message: List.first(messages)}}
  end

  defp identity_result(result), do: result

  @impl true
  def configuration_reference(_request, _result), do: nil
end
