defmodule Cadence.Telemetry.LogSink do
  @moduledoc """
  Behaviour for durable telemetry sinks (OTP append log, Kafka, Redpanda).

  Implementations are responsible for persisting batches of `t:Cadence.Telemetry.LogEnvelope/0`
  while retaining shard ordering.
  """

  alias Cadence.Telemetry.LogEnvelope

  @type append_meta :: %{
          optional(:first_offset) => term(),
          optional(:last_offset) => term(),
          optional(:duration_ms) => non_neg_integer()
        }

  @callback append(
              shard_id :: non_neg_integer(),
              records :: [LogEnvelope.t()],
              opts :: keyword()
            ) ::
              {:ok, append_meta()} | {:error, term()}

  @callback partitions() :: {:ok, [non_neg_integer()]} | {:error, term()}
  @callback health() :: {:ok, map()} | {:error, term()}
end
