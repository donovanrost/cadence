defmodule Cadence.Telemetry.LogSource do
  @moduledoc """
  Behaviour for consuming telemetry from a durable sink.

  The source is responsible for fan-out to consumers (CVT, post-processing,
  replay tooling) while respecting shard ordering and consumer offsets.
  """

  alias Cadence.Telemetry.LogEnvelope

  @type subscription_meta :: %{
          shard_id: non_neg_integer(),
          group: term(),
          start_from: term()
        }

  @callback subscribe(
              shard_id :: non_neg_integer(),
              opts :: keyword()
            ) ::
              {:ok, pid(), subscription_meta()} | {:error, term()}

  @callback ack(shard_id :: non_neg_integer(), offset :: term(), opts :: keyword()) ::
              :ok | {:error, term()}

  @callback partitions() :: {:ok, [non_neg_integer()]} | {:error, term()}
  @callback health() :: {:ok, map()} | {:error, term()}

  @callback handle_batch(pid(), [LogEnvelope.t()], keyword()) :: any()
end
