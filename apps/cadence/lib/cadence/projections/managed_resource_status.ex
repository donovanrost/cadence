defmodule Cadence.Projections.ManagedResourceStatus do
  @moduledoc "Read model separating desired data-source state from lifecycle execution."

  alias Cadence.Control.ManagedResources, as: ControlManagedResources
  alias Cadence.DataSources.DeploymentStatus
  alias Cadence.Management.ManagedResources

  @spec project(binary()) :: {:ok, map()} | {:error, term()}
  def project(data_source_id) do
    with {:ok, source} <- ManagedResources.fetch_data_source(data_source_id) do
      {:ok,
       %{
         requested: %{data_source: source},
         operational: %{deployment: DeploymentStatus.from_data_source(source)},
         applied: %{lifecycle: lifecycle(source)},
         observed: %{health: Map.get(source.metadata, "health", %{})}
       }}
    end
  end

  @spec deployment_runs(binary()) :: [map()]
  def deployment_runs(mission_id) do
    ControlManagedResources.list_managed_questdb_runs(mission_id) ++
      ControlManagedResources.list_tsdb_backend_runs(mission_id)
  end

  defp lifecycle(source), do: Map.get(source.metadata, "tsdb_backend_lifecycle", %{})
end
