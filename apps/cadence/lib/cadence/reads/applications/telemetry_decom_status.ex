defmodule Cadence.Reads.Applications.TelemetryDecomStatus do
  @moduledoc "Composes Telemetry Decom configuration and active-runtime status for a host."

  @behaviour Cadence.Reads.Applications.StatusProvider

  alias Cadence.Applications.{HostContext, Status, TelemetryDecom}
  alias Cadence.Auth.Scope

  @impl true
  def load(
        %Scope{organization_id: organization_id},
        %HostContext{
          placement: :spacecraft,
          mission_id: mission_id,
          spacecraft_id: spacecraft_id
        }
      )
      when is_binary(organization_id) do
    config = load_configuration(organization_id, mission_id, spacecraft_id)
    active = load_active_binding_set(organization_id, mission_id)

    {:ok, status(config, active)}
  end

  def load(%Scope{}, %HostContext{}), do: {:error, :unsupported_application_host_context}

  defp load_configuration(organization_id, mission_id, spacecraft_id) do
    case TelemetryDecom.fetch_config(organization_id, mission_id, spacecraft_id) do
      {:ok, config} -> config
      {:error, :not_configured} -> nil
    end
  end

  defp load_active_binding_set(organization_id, mission_id) do
    case Cadence.Activations.fetch_active_activation(organization_id, mission_id) do
      {:ok, activation} ->
        %{
          binding_set_id: activation.binding_set_id,
          binding_set_version: activation.binding_set_version
        }

      {:error, _reason} ->
        nil
    end
  end

  defp status(config, active) do
    config
    |> TelemetryDecom.status(active)
    |> to_status()
  end

  defp to_status(:applied) do
    new_status(:applied, "Applied", :ready, "Configured", "Live")
  end

  defp to_status(:configured) do
    new_status(:configured, "Configured", :attention, "Configured", "Saved, not live")
  end

  defp to_status(:outdated) do
    new_status(:outdated, "Out of date", :attention, "Configured", "Needs apply")
  end

  defp to_status(:disabled) do
    new_status(:disabled, "Disabled", :blocked, "Disabled", "Disabled")
  end

  defp to_status(:not_configured) do
    new_status(:not_configured, "Not configured", :blocked, "None", "Not published")
  end

  defp new_status(state, label, tone, packet_claims, publication) do
    %Status{
      state: state,
      label: label,
      tone: tone,
      facts: [
        %{id: "packet_claims", label: "Packet claims", value: packet_claims},
        %{id: "publication", label: "Publication", value: publication}
      ]
    }
  end
end
