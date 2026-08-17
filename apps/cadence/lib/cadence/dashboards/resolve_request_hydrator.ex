defmodule Cadence.Dashboards.ResolveRequestHydrator do
  @moduledoc """
  Persistence boundary that materializes dashboard library references.

  Hydration may read pinned dashboard-library versions from the repository.
  Planning consumes the resulting `HydratedResolveRequest` and does not perform
  this persistence step itself.
  """

  alias Cadence.Dashboards.{
    DashboardResolveRequest,
    Document,
    HydratedResolveRequest,
    Management
  }

  @spec hydrate(DashboardResolveRequest.t()) :: HydratedResolveRequest.t()
  def hydrate(%DashboardResolveRequest{} = request) do
    request = DashboardResolveRequest.normalize(request)

    request
    |> hydrate_document()
    |> HydratedResolveRequest.new!()
  end

  defp hydrate_document(%DashboardResolveRequest{document: %Document{} = document} = request) do
    %DashboardResolveRequest{request | document: Management.resolve_document(document)}
  end

  defp hydrate_document(%DashboardResolveRequest{} = request), do: request
end
