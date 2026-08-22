defmodule Cadence.Telemetry.PacketLogRecord do
  @moduledoc """
  Record written to the append-only telemetry log for v2 pipeline stages.
  """

  @type record_type :: :envelope | :classification | :decom_result

  @type t :: %__MODULE__{
          record_type: record_type(),
          mission_id: binary(),
          lane: atom(),
          shard_id: non_neg_integer(),
          packet_id: binary(),
          payload: map(),
          meta: map()
        }

  defstruct [:record_type, :mission_id, :lane, :shard_id, :packet_id, payload: %{}, meta: %{}]

  @spec envelope_record(Cadence.Telemetry.PacketEnvelope.t(), atom(), non_neg_integer()) :: t()
  def envelope_record(envelope, lane, shard_id) do
    %__MODULE__{
      record_type: :envelope,
      mission_id: envelope.mission_id,
      lane: lane,
      shard_id: shard_id,
      packet_id: envelope.packet_id,
      payload: %{
        ingest_ts: envelope.ingest_ts,
        ingest_monotonic_ns: envelope.ingest_monotonic_ns,
        raw: envelope.raw,
        provenance: envelope.provenance,
        evidence: envelope.evidence,
        router_version: envelope.router_version,
        config_version_seen: envelope.config_version_seen,
        mode: envelope.mode,
        quality: envelope.quality,
        observations: envelope.observations
      }
    }
  end

  @spec classification_record(Cadence.Telemetry.ResolvedUnit.t(), atom(), non_neg_integer()) ::
          t()
  def classification_record(resolved, lane, shard_id) do
    %__MODULE__{
      record_type: :classification,
      mission_id: resolved.mission_id,
      lane: lane,
      shard_id: shard_id,
      packet_id: resolved.packet_id,
      payload: %{
        config_version_used: resolved.config_version_used,
        identity_result: resolved.identity,
        schema_result: resolved.schema,
        format: resolved.format,
        decision_trace: resolved.decision_trace
      }
    }
  end

  @spec decom_record(
          Cadence.Telemetry.ResolvedUnit.t(),
          map(),
          non_neg_integer(),
          atom(),
          non_neg_integer(),
          binary() | nil
        ) :: t()
  def decom_record(resolved, items, apid, lane, shard_id, target_identifier) do
    target_id =
      case resolved.identity do
        {:ok, id} -> id
        _ -> nil
      end

    packet_def_name =
      case resolved.schema do
        {:ok, packet_def} -> Map.get(packet_def, :name)
        _ -> nil
      end

    %__MODULE__{
      record_type: :decom_result,
      mission_id: resolved.mission_id,
      lane: lane,
      shard_id: shard_id,
      packet_id: resolved.packet_id,
      payload: %{
        target_id: target_id,
        target_identifier: target_identifier,
        apid: apid,
        packet_def_name: packet_def_name,
        items: items
      }
    }
  end
end
