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
    Document,
    Engine,
    HydratedResolveRequest,
    ResolutionContext,
    ResolveRequestHydrator
  }

  @spec resolve(DashboardResolveRequest.t(), ResolutionContext.t()) ::
          DashboardResolveResult.t()
  def resolve(%DashboardResolveRequest{} = request, %ResolutionContext{} = context) do
    {_document, result} = resolve_with_document(request, context)
    result
  end

  @doc """
  Resolves and returns the exact hydrated document used by the engine.

  Presentation callers must not independently re-fetch mutable library references
  or silently drop unavailable placements when joining definitions to frames.
  """
  @spec resolve_with_document(DashboardResolveRequest.t(), ResolutionContext.t()) ::
          {Document.t(), DashboardResolveResult.t()}
  def resolve_with_document(%DashboardResolveRequest{} = request, %ResolutionContext{} = context) do
    hydrated = ResolveRequestHydrator.hydrate(request)
    result = Engine.resolve_hydrated(hydrated, ResolutionContext.to_engine_opts(context))
    {HydratedResolveRequest.unwrap(hydrated).document, result}
  end
end
