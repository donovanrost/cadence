defmodule Cadence.Applications.DerivedTelemetry do
  @moduledoc "Application-owned contribution metadata for Derived Telemetry."

  alias Cadence.Applications.SurfaceQueryContribution

  @application_key "derived_telemetry"

  @spec application_key() :: binary()
  def application_key, do: @application_key

  @spec action_provider() :: module()
  def action_provider, do: Cadence.Applications.DerivedTelemetry.ActionProvider

  @spec surface_query_contributions() :: [SurfaceQueryContribution.t()]
  def surface_query_contributions do
    [
      %SurfaceQueryContribution{
        application_key: @application_key,
        application_version: 1,
        query_id: "cadence.derived_telemetry.manage",
        query_version: 1,
        provider: Cadence.Reads.ApplicationSurfaces.DerivedTelemetry
      }
    ]
  end
end
