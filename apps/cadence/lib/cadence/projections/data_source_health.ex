defmodule Cadence.Projections.DataSourceHealth do
  @moduledoc """
  Projection boundary for observing dashboard source health and capabilities.

  A probe samples an external read source and records downstream diagnostic
  facts; it does not change operational intent or make source configuration
  authoritative outside the management plane.
  """

  alias Cadence.Dashboards.DataSources.SourceOperations
  alias Cadence.Management.DataSources

  @spec probe(binary(), map(), keyword()) :: term()
  def probe(data_source_id, attrs \\ %{}, opts \\ [])
      when is_binary(data_source_id) and is_map(attrs) and is_list(opts) do
    SourceOperations.probe_data_source(
      data_source_id,
      attrs,
      opts,
      {&DataSources.fetch_data_source/1, &DataSources.persist_data_source/2}
    )
  end
end
