defmodule CadenceWeb.API.ReadParams do
  @moduledoc "Projection and telemetry query parsing boundary."

  alias CadenceWeb.ControlPlaneParams, as: LegacyParams

  defdelegate mission_health_filters(params), to: LegacyParams
  defdelegate mission_event_filters(params), to: LegacyParams
  defdelegate telemetry_latest_filters(params), to: LegacyParams
  defdelegate telemetry_history_filters(params), to: LegacyParams
end
