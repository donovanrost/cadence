defmodule CadenceWeb.ApplicationSurfaceRegistry do
  @moduledoc "Explicit allow-list of compiled first-party application surface adapters."

  alias CadenceWeb.ApplicationSurfaces.TelemetryDecom

  @surfaces %{
    "cadence.telemetry_decom.manage" => TelemetryDecom
  }

  @spec fetch(binary()) :: {:ok, module()} | {:error, :unknown_application_renderer}
  def fetch(renderer_id) when is_binary(renderer_id) do
    case Map.fetch(@surfaces, renderer_id) do
      {:ok, surface} -> {:ok, surface}
      :error -> {:error, :unknown_application_renderer}
    end
  end

  def fetch(_renderer_id), do: {:error, :unknown_application_renderer}
end
