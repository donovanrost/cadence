defmodule Cadence.Control.DataSources do
  @moduledoc """
  Control boundary for actively probing Data Source health and capabilities.

  A probe samples an external read source and records downstream diagnostic
  facts; it does not change operational intent or make source configuration
  authoritative outside the management plane.
  """

  alias Cadence.Control.DataSources.SourceOperations
  alias Cadence.Management.DataSources
  alias Cadence.Projections.DataSources.Health

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

  @spec record_health_observation(map(), keyword()) :: term()
  def record_health_observation(attrs, opts \\ []) when is_map(attrs) and is_list(opts) do
    Health.record_source_health(attrs, opts)
  end
end
