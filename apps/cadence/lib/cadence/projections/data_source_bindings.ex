defmodule Cadence.Projections.DataSourceBindings do
  @moduledoc """
  Projection boundary for resolving effective dashboard source bindings.
  """

  alias Cadence.Dashboards.{DataSourceRegistry, PlannedSourceRequest, ResolvedSourceBinding}
  alias Cadence.Dashboards.ResolveWarning
  alias Cadence.Management.DataSources
  alias Cadence.Projections.DataSources.Health, as: SourceHealth

  @spec resolve(PlannedSourceRequest.t(), keyword()) ::
          {:ok, ResolvedSourceBinding.t()} | {:error, ResolveWarning.t()}
  def resolve(%PlannedSourceRequest{} = request, opts \\ []) when is_list(opts) do
    registry_opts =
      [
        data_sources: DataSources.list_data_sources(request.organization_id, request.mission_id),
        data_bindings:
          DataSources.list_data_bindings(request.organization_id, request.mission_id),
        source_health_statuses:
          SourceHealth.list_source_health_statuses(request.organization_id, request.mission_id,
            logical_source: request.logical_source
          )
      ]
      |> Keyword.merge(opts)

    DataSourceRegistry.resolve(request, registry_opts)
  end
end
