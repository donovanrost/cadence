defmodule Cadence.Applications.ApplicationBindingStore do
  @moduledoc "Read projection of application bindings from spacecraft configuration heads."

  alias Cadence.Applications.ApplicationBinding
  alias Cadence.Applications.SpacecraftConfiguration.TelemetryDecomProjection

  @spec list(binary(), binary(), keyword()) :: [ApplicationBinding.t()]
  def list(organization_id, mission_id, application_key: "telemetry_decom") do
    organization_id
    |> TelemetryDecomProjection.list(mission_id)
    |> Enum.map(fn config ->
      config
      |> Map.from_struct()
      |> Map.put(:application_key, "telemetry_decom")
      |> ApplicationBinding.new()
    end)
  end
end
