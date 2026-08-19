defmodule Cadence.Dashboards.Resolution do
  @moduledoc """
  Application boundary for dashboard resolution.

  This service owns persistence-backed request hydration. The dashboard engine
  receives a typed hydrated request plus an explicit `ResolutionContext` and
  remains usable below the persistence boundary.
  """

  alias Cadence.Dashboards.{
    DashboardResolveRequest,
    DashboardResolveResult,
    Engine,
    ResolutionContext,
    ResolveRequestHydrator
  }

  @spec resolve(DashboardResolveRequest.t(), ResolutionContext.t()) ::
          DashboardResolveResult.t()
  def resolve(%DashboardResolveRequest{} = request, %ResolutionContext{} = context) do
    request
    |> ResolveRequestHydrator.hydrate()
    |> Engine.resolve_hydrated(ResolutionContext.to_engine_opts(context))
  end
end
