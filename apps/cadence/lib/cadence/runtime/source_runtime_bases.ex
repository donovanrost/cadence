defmodule Cadence.Runtime.SourceRuntimeBases do
  @moduledoc """
  Source-to-model references with one stored copy of each distinct runtime basis.

  Sharing nested terms on one BEAM heap does not survive ordinary process messages.
  This representation stays compact when a fleet specification is sent, returned
  from a coordinator, or serialized. Model keys are local references, not identities;
  runtime identity is still computed from each source's resolved basis.
  """

  @type t :: %__MODULE__{sources: %{binary() => non_neg_integer()}, models: map()}
  defstruct sources: %{}, models: %{}

  @fields [:mission_model_revision_id, :mission_model_content_sha256, :runtime_plans]

  @spec new(map()) :: {:ok, t()} | {:error, :invalid_source_runtime_bases}
  def new(%__MODULE__{sources: sources, models: models} = index)
      when is_map(sources) and is_map(models) and map_size(sources) in 1..1000 do
    valid? =
      Enum.all?(sources, fn {source, key} ->
        valid_source?(source) and is_integer(key) and key >= 0 and Map.has_key?(models, key)
      end) and
        MapSet.new(Map.values(sources)) == MapSet.new(Map.keys(models)) and
        Enum.all?(models, fn {_key, basis} -> is_map(basis) end)

    if valid?, do: {:ok, index}, else: {:error, :invalid_source_runtime_bases}
  end

  def new(%__MODULE__{}), do: {:error, :invalid_source_runtime_bases}

  def new(sources) when is_map(sources) and map_size(sources) in 1..1000 do
    sources
    |> Enum.reduce_while({:ok, %__MODULE__{}, %{}}, fn {source, basis}, {:ok, index, keys} ->
      if valid_source?(source) and is_map(basis) do
        basis = Map.take(basis, @fields)
        key = Map.get(keys, basis, map_size(keys))

        index = %{
          index
          | sources: Map.put(index.sources, source, key),
            models: Map.put_new(index.models, key, basis)
        }

        {:cont, {:ok, index, Map.put_new(keys, basis, key)}}
      else
        {:halt, {:error, :invalid_source_runtime_bases}}
      end
    end)
    |> case do
      {:ok, index, _keys} -> {:ok, index}
      error -> error
    end
  end

  def new(_), do: {:error, :invalid_source_runtime_bases}

  @spec fetch(t(), binary()) :: {:ok, map()} | :error
  def fetch(%__MODULE__{} = index, source) do
    with {:ok, key} <- Map.fetch(index.sources, source), do: Map.fetch(index.models, key)
  end

  @spec take(t(), [binary()]) :: t()
  def take(%__MODULE__{} = index, sources) do
    refs = Map.take(index.sources, sources)
    %{index | sources: refs, models: Map.take(index.models, Map.values(refs))}
  end

  @spec count(t()) :: non_neg_integer()
  def count(%__MODULE__{} = index), do: map_size(index.sources)

  defp valid_source?(source), do: is_binary(source) and byte_size(source) in 1..255
end
