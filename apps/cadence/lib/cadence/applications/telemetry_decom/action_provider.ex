defmodule Cadence.Applications.TelemetryDecom.ActionProvider do
  @moduledoc "Typed action adapter for Telemetry Decom management operations."

  @behaviour Cadence.Applications.ActionProvider

  alias Cadence.Applications.{ActionRequest, ConfigurationReference, HostContext, TelemetryDecom}
  alias Cadence.Applications.TelemetryDecom.Config
  alias Cadence.Auth.Scope

  @impl true
  def execute(
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

  def execute(
        %Scope{} = current_scope,
        %HostContext{
          placement: :spacecraft,
          mission_id: mission_id,
          spacecraft_id: spacecraft_id
        },
        %ActionRequest{action_id: "request_activation"}
      ) do
    TelemetryDecom.request_mission_apply(current_scope, mission_id, spacecraft_id)
  end

  def execute(
        %Scope{organization_id: organization_id},
        %HostContext{
          placement: :spacecraft,
          mission_id: mission_id,
          spacecraft_id: spacecraft_id
        },
        %ActionRequest{action_id: "disable"}
      ) do
    TelemetryDecom.disable(organization_id, mission_id, spacecraft_id)
  end

  def execute(%Scope{}, %HostContext{}, %ActionRequest{}),
    do: {:error, :unsupported_application_action}

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
end
