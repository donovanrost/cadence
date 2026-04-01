defmodule Cadence.Telemetry.LogEnvelope do
  @moduledoc """
  Shared record envelope for durable telemetry logs.

  Encapsulates the per-packet metadata we persist to the log, regardless of the
  backing adapter (OTP disk log, Kafka, etc).
  """

  @type t :: %__MODULE__{
          mission_id: String.t(),
          target_id: String.t() | nil,
          apid: non_neg_integer() | nil,
          lane: atom(),
          shard_id: non_neg_integer(),
          router_version: non_neg_integer(),
          config_version: non_neg_integer(),
          sequence: non_neg_integer() | nil,
          ingest_monotonic_ns: non_neg_integer(),
          source_wall_clock_ms: non_neg_integer() | nil,
          checksum: binary() | nil,
          payload: map(),
          meta: map()
        }

  defstruct [
    :mission_id,
    :target_id,
    :apid,
    :lane,
    :shard_id,
    :router_version,
    :config_version,
    :sequence,
    :ingest_monotonic_ns,
    :source_wall_clock_ms,
    :checksum,
    payload: %{},
    meta: %{}
  ]
end
