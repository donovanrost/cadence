defmodule Cadence.Applications.TelemetryDecom.ActionProvider do
  @moduledoc "Typed action adapter for Telemetry Decom management operations."

  @behaviour Cadence.Applications.ActionProvider

  alias Cadence.Applications.ActionContractLedger

  alias Cadence.Applications.{
    ActionFailure,
    ActionRequest,
    ApplicationInstallations,
    ConfigurationReference,
    HostContext,
    PacketBindings,
    TelemetryDecom
  }

  alias Cadence.Applications.TelemetryDecom.{Config, Review}
  alias Cadence.Auth.Scope

  @surface_action_bindings [
    {"manage", 1, "save_configuration"},
    {"manage", 1, "request_activation"},
    {"manage", 1, "disable"},
    {"packet_bindings", 1, "save_packet_bindings"}
  ]

  @impl true
  def application_key, do: "telemetry_decom"

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
      scope |> execute_reviewed(host_context, request) |> review_result()
    end
  end

  defp review_result({:error, :telemetry_decom_review_conflict}) do
    {:error,
     %ActionFailure{
       code: "review_conflict",
       message:
         "Telemetry configuration or packet inputs changed. Refresh this page, review the current evidence, and submit again."
     }}
  end

  defp review_result({:error, :telemetry_decom_review_required}) do
    {:error,
     %ActionFailure{
       code: "review_required",
       message:
         "Refresh this page and review the current telemetry configuration before submitting."
     }}
  end

  defp review_result({:error, :mission_model_revision_not_approved}) do
    {:error,
     %ActionFailure{
       code: "mission_model_approval_required",
       message: "Approve the mission model revision in Catalog before requesting mission changes."
     }}
  end

  defp review_result({:error, {:telemetry_decom_requires_one_mission_model_revision, _ids}}) do
    {:error,
     %ActionFailure{
       code: "mission_model_revision_mismatch",
       message:
         "Enabled configurations must use one mission model revision before requesting mission changes."
     }}
  end

  defp review_result(result), do: result

  defp execute_reviewed(
         %Scope{organization_id: organization_id} = scope,
         %HostContext{
           placement: :spacecraft,
           mission_id: mission_id,
           spacecraft_id: spacecraft_id
         } = host,
         %ActionRequest{action_id: action, params: params} = request
       )
       when action in [
              "save_configuration",
              "request_activation",
              "disable",
              "save_packet_bindings"
            ] do
    Review.run(organization_id, mission_id, spacecraft_id, action, params, fn ->
      execute_action(scope, host, request)
    end)
  end

  defp execute_reviewed(scope, host, request), do: execute_action(scope, host, request)

  defp execute_action(
         %Scope{organization_id: organization_id},
         %HostContext{
           placement: :spacecraft,
           mission_id: mission_id,
           spacecraft_id: spacecraft_id
         },
         %ActionRequest{action_id: "save_configuration", params: params}
       ) do
    TelemetryDecom.configure(organization_id, mission_id, spacecraft_id, params)
  end

  defp execute_action(
         %Scope{} = current_scope,
         %HostContext{placement: :spacecraft} = host_context,
         %ActionRequest{action_id: "save_packet_bindings", params: params}
       ) do
    with :ok <- packet_catalog_matches(current_scope, host_context, params),
         {:ok, installation} <-
           ApplicationInstallations.fetch_installed(
             current_scope,
             host_context,
             "telemetry_decom"
           ) do
      PacketBindings.replace(
        current_scope,
        host_context,
        installation.application_installation_id,
        params
      )
    end
  end

  defp execute_action(
         %Scope{} = current_scope,
         %HostContext{
           placement: :spacecraft,
           mission_id: mission_id,
           spacecraft_id: spacecraft_id
         },
         %ActionRequest{action_id: "request_activation", params: params}
       ) do
    TelemetryDecom.request_mission_apply(current_scope, mission_id, spacecraft_id,
      reviewed_configuration_basis:
        Map.get(params, "expected_review", Map.get(params, :expected_review))
    )
  end

  defp execute_action(
         %Scope{organization_id: organization_id} = current_scope,
         %HostContext{
           placement: :spacecraft,
           mission_id: mission_id,
           spacecraft_id: spacecraft_id
         } = host_context,
         %ActionRequest{action_id: "disable"}
       ) do
    with {:ok, installation} <-
           ApplicationInstallations.fetch_installed(
             current_scope,
             host_context,
             "telemetry_decom"
           ),
         {:ok, _packet_configurations} <-
           PacketBindings.disable(
             current_scope,
             host_context,
             installation.application_installation_id
           ) do
      TelemetryDecom.disable(organization_id, mission_id, spacecraft_id)
    end
  end

  defp execute_action(%Scope{}, %HostContext{}, %ActionRequest{}),
    do: {:error, :application_action_scope_required}

  defp packet_catalog_matches(scope, host, params) do
    with {:ok, config} <-
           TelemetryDecom.fetch_config(scope.organization_id, host.mission_id, host.spacecraft_id),
         true <-
           config.catalog_revision_id ==
             Map.get(params, "catalog_revision_id", Map.get(params, :catalog_revision_id)) do
      :ok
    else
      _ ->
        {:error,
         %ActionFailure{
           code: "review_conflict",
           message:
             "The configured catalog revision changed or is unavailable. Open Manage and review the current configuration before saving packet inputs."
         }}
    end
  end

  defp ensure_surface_binding(%ActionRequest{} = request),
    do: ActionContractLedger.admit(request, __MODULE__)

  @impl true
  def configuration_reference(
        %ActionRequest{action_id: "save_configuration"},
        %Config{} = config
      ) do
    %ConfigurationReference{
      kind: "spacecraft_application_binding",
      id: "application_binding:#{config.spacecraft_id}:telemetry_decom",
      version: config.configuration_version
    }
  end

  def configuration_reference(%ActionRequest{}, _result), do: nil

  @impl true
  def result(%Cadence.Applications.PacketBindingConfiguration{} = configuration) do
    %{
      "configurationId" => configuration.packet_binding_configuration_id,
      "applicationKey" => configuration.application_key,
      "applicationVersion" => configuration.application_version,
      "inputId" => configuration.input_id,
      "inputVersion" => configuration.input_version,
      "configurationVersion" => configuration.configuration_version,
      "enabled" => configuration.enabled,
      "selectedPacketIds" => Enum.map(configuration.bindings, & &1.packet_id),
      "bindingCount" => length(configuration.bindings)
    }
  end

  def result(%Config{} = configuration) do
    %{
      "configurationId" => "telemetry_decom:#{configuration.spacecraft_id}",
      "configurationVersion" => configuration.configuration_version,
      "enabled" => configuration.enabled,
      "selectedApids" => configuration.handled_apids
    }
  end

  def result(%{config: %Config{} = config, activation_request: request}) do
    %{
      "configurationId" => "telemetry_decom:#{config.spacecraft_id}",
      "configurationVersion" => config.configuration_version,
      "activationRequestId" => request.activation_request_id,
      "activationState" => to_string(request.state),
      "bindingSetId" => request.binding_set_id,
      "bindingSetVersion" => request.binding_set_version
    }
  end

  def result(value) when is_map(value), do: value
  def result(_value), do: nil
end
