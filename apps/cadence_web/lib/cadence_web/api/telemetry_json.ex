defmodule CadenceWeb.API.TelemetryJSON do
  @moduledoc "Telemetry and data-plane ingress response serialization boundary."

  alias CadenceWeb.ControlPlaneJSON, as: LegacyJSON

  defdelegate telemetry_sample(value), to: LegacyJSON
  defdelegate dev_ingress_result(value), to: LegacyJSON
end
