defmodule CadenceWeb.ApplicationSurfaces.TelemetryDecom do
  @moduledoc "Trusted surface adapter preserving the existing Telemetry Decom workflow."

  @behaviour CadenceWeb.ApplicationSurface

  alias CadenceWeb.SpacecraftTelemetryDecomLive

  @impl true
  def mount(socket), do: SpacecraftTelemetryDecomLive.mount_surface(socket)

  @impl true
  def handle_event(event, params, socket) do
    SpacecraftTelemetryDecomLive.handle_event(event, params, socket)
  end

  @impl true
  def render(assigns), do: SpacecraftTelemetryDecomLive.render(assigns)
end
