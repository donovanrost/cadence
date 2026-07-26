defmodule Cadence.Reads.Applications.DerivedTelemetryStatus do
  @moduledoc "Host-standard status projection for the Derived Telemetry application."

  @behaviour Cadence.Reads.Applications.StatusProvider

  alias Cadence.Applications.{HostContext, Status}
  alias Cadence.Auth.Scope
  alias Cadence.Governance
  alias Cadence.Reads.DerivedTelemetry, as: DerivedTelemetryReads

  @impl true
  def load(
        %Scope{organization_id: organization_id},
        %HostContext{placement: :mission, mission_id: mission_id}
      )
      when is_binary(organization_id) do
    definition_count = mission_id |> Governance.list_derived_definitions() |> length()

    latest_value_count =
      organization_id
      |> DerivedTelemetryReads.latest_values_for_mission(mission_id, [])
      |> length()

    {:ok, status(definition_count, latest_value_count)}
  end

  def load(%Scope{}, %HostContext{}), do: {:error, :unsupported_application_host_context}

  defp status(0, latest_value_count) do
    %Status{
      state: :not_configured,
      label: "Not configured",
      tone: :attention,
      facts: facts(0, latest_value_count)
    }
  end

  defp status(definition_count, latest_value_count) do
    %Status{
      state: :configured,
      label: "Configured",
      tone: :ready,
      facts: facts(definition_count, latest_value_count)
    }
  end

  defp facts(definition_count, latest_value_count) do
    [
      %{id: "definitions", label: "Definitions", value: Integer.to_string(definition_count)},
      %{
        id: "latest_values",
        label: "Current values",
        value: Integer.to_string(latest_value_count)
      }
    ]
  end
end
