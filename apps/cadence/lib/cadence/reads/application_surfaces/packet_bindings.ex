defmodule Cadence.Reads.ApplicationSurfaces.PacketBindings do
  @moduledoc "Compatibility query identity for the domain-owned Telemetry Decom packet feature."
  @behaviour Cadence.Reads.ApplicationSurfaces.SurfaceQueryProvider

  @impl true
  def application_key, do: "telemetry_decom"

  @impl true
  defdelegate load(scope, host, request),
    to: Cadence.Reads.ApplicationSurfaces.TelemetryDecom.PacketBindings
end
