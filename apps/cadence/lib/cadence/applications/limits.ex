defmodule Cadence.Applications.Limits do
  @moduledoc "Application-owned contribution metadata for mission limits."

  alias Cadence.Applications.SurfaceQueryContribution

  @application_key "limits"

  @spec application_key() :: binary()
  def application_key, do: @application_key

  @spec action_provider() :: module()
  def action_provider, do: Cadence.Applications.Limits.ActionProvider

  @spec surface_query_contributions() :: [SurfaceQueryContribution.t()]
  def surface_query_contributions do
    [
      %SurfaceQueryContribution{
        application_key: @application_key,
        application_version: 1,
        query_id: "cadence.limits.manage",
        query_version: 1,
        provider: Cadence.Reads.ApplicationSurfaces.Limits
      },
      %SurfaceQueryContribution{
        application_key: @application_key,
        application_version: 1,
        query_id: "cadence.limits.activity",
        query_version: 1,
        provider: Cadence.Reads.ApplicationSurfaces.Limits
      }
    ]
  end
end
