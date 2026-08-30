defmodule Cadence.Applications.TelemetryDecomCatalogContribution do
  @moduledoc "Application-owned frontend release contributions for Telemetry Decom."

  alias Cadence.Applications.ReleaseContribution

  @spec release_contributions() :: [ReleaseContribution.t()]
  def release_contributions do
    [
      %ReleaseContribution{
        application_key: "telemetry_decom",
        application_version: 1,
        surface_id: "packet_bindings",
        surface_version: 1,
        federation: :module_federation,
        release_id: "telemetry-decom-v1",
        remote_name: "cadence_telemetry_decom",
        manifest_path: "/assets/application-host/telemetry-decom/mf-manifest.json",
        exposed_module: "./Application"
      }
    ]
  end
end
