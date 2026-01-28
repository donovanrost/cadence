defmodule Cadence.Runtime.Telemetry.PipelineEvent do
  @moduledoc """
  Event flowing through the v2 telemetry pipeline.
  """

  @type t :: %__MODULE__{
          packet_id: binary(),
          mission_id: binary(),
          lane: atom(),
          shard_id: non_neg_integer(),
          router_version: non_neg_integer() | nil,
          config_version: non_neg_integer(),
          envelope: Cadence.Telemetry.PacketEnvelope.t(),
          parsed_unit: Cadence.Telemetry.ParsedUnit.t() | nil,
          parse_error: term() | nil,
          resolved_unit: Cadence.Telemetry.ResolvedUnit.t() | nil,
          ingest_monotonic_ns: non_neg_integer()
        }

  defstruct [
    :packet_id,
    :mission_id,
    :lane,
    :shard_id,
    :router_version,
    :config_version,
    :envelope,
    :parsed_unit,
    :parse_error,
    :resolved_unit,
    :ingest_monotonic_ns
  ]
end
