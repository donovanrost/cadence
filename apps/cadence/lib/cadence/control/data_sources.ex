defmodule Cadence.Control.DataSources do
  @moduledoc """
  Control boundary for actively probing Data Source health and capabilities.

  A probe samples an external read source and records downstream diagnostic
  facts; it does not change operational intent or make source configuration
  authoritative outside the management plane.
  """

  alias Cadence.Control.DataSources.SourceOperations
  alias Cadence.DataSources.SourceProbe
  alias Cadence.Management.DataSources
  alias Cadence.Projections.DataSources.Health

  @spec probe(binary(), map(), keyword()) :: term()
  def probe(data_source_id, attrs \\ %{}, opts \\ [])
      when is_binary(data_source_id) and is_map(attrs) and is_list(opts) do
    with {:ok, prepared_probe} <- prepare_probe(data_source_id, attrs, opts) do
      prepared_probe
      |> observe_probe()
      |> then(&persist_probe(prepared_probe, &1))
    end
  end

  @doc false
  @spec prepare_probe(binary(), map(), keyword()) ::
          {:ok, SourceOperations.prepared_probe()} | {:error, term()}
  def prepare_probe(data_source_id, attrs, opts)
      when is_binary(data_source_id) and is_map(attrs) and is_list(opts) do
    SourceOperations.prepare_data_source_probe(
      data_source_id,
      attrs,
      opts,
      &DataSources.fetch_data_source/1
    )
  end

  @doc false
  @spec observe_probe(SourceOperations.prepared_probe()) :: SourceProbe.t()
  def observe_probe(prepared_probe) do
    SourceOperations.observe_data_source_probe(prepared_probe)
  end

  @doc false
  @spec persist_probe(SourceOperations.prepared_probe(), SourceProbe.t()) :: term()
  def persist_probe(prepared_probe, %SourceProbe{} = probe) do
    SourceOperations.persist_data_source_probe(
      prepared_probe,
      probe,
      &DataSources.persist_data_source/2
    )
  end

  @spec record_health_observation(map(), keyword()) :: term()
  def record_health_observation(attrs, opts \\ []) when is_map(attrs) and is_list(opts) do
    Health.record_source_health(attrs, opts)
  end
end
