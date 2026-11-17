defmodule Cadence.Runtime.PartitionOwner.EffectIds do
  @moduledoc """
  Gives a partition's monitoring effects their replay-safe ids (DECISIONS #99,
  `Cadence.Platform.ReplayId`) just before they are persisted, and resolves the stream ordinals
  the alarm writer needs.

  Ordinals come from `PartitionStreamKeys` (one statement the first time a stream is seen) and are
  cached in the partition owner's process for its life, so a stream costs one statement per
  partition start, not one per batch.
  """

  alias Cadence.Platform.ReplayId
  alias Cadence.Runtime.{ManagedActionRequest, PartitionKey, PartitionStreamKeys}

  @cache {__MODULE__, :ordinals}

  @doc "Action requests with an effect source get their replay-safe id; others keep theirs."
  @spec assign(map()) :: {:ok, map()} | {:error, term()}
  def assign(%{action_requests: []} = records), do: {:ok, records}

  def assign(%{action_requests: [first | _] = requests} = records) do
    partition_id =
      PartitionKey.identifier(%PartitionKey{
        affinity: first.partition_affinity,
        value: first.partition_value
      })

    sources = Enum.map(requests, & &1.effect_source)

    with {:ok, ordinals} <-
           ordinals(first.mission_id, partition_id, ReplayId.stream_keys(sources)) do
      requests =
        requests
        |> ReplayId.number(& &1.effect_source, ordinals)
        |> Enum.map(fn
          {request, nil} ->
            request

          {%ManagedActionRequest{} = request, key} ->
            %{request | action_request_id: ReplayId.id(:managed_action_request, key)}
        end)

      {:ok, %{records | action_requests: requests}}
    end
  end

  @doc "The ordinals of `stream_keys` in this partition, allocating new ones."
  @spec ordinals(binary(), binary(), [binary()]) ::
          {:ok, %{optional(binary()) => pos_integer()}} | {:error, term()}
  def ordinals(mission_id, partition_id, stream_keys) do
    cache = Process.get(@cache, %{})

    Enum.reduce_while(stream_keys, {:ok, %{}}, fn stream, {:ok, acc} ->
      case Map.fetch(cache, {mission_id, partition_id, stream}) do
        {:ok, ordinal} ->
          {:cont, {:ok, Map.put(acc, stream, ordinal)}}

        :error ->
          case PartitionStreamKeys.ordinal(mission_id, partition_id, stream) do
            {:ok, ordinal} ->
              Process.put(
                @cache,
                Map.put(Process.get(@cache, %{}), {mission_id, partition_id, stream}, ordinal)
              )

              {:cont, {:ok, Map.put(acc, stream, ordinal)}}

            {:error, reason} ->
              {:halt, {:error, {:partition_stream_key_failed, stream, reason}}}
          end
      end
    end)
  end
end
