defmodule Cadence.Runtime.Telemetry.PipelineV2.PipelineEvent do
  @moduledoc """
  Event structure flowing through the V2 telemetry pipeline stages.

  Each event represents a single packet being processed. As it flows through
  stages (Identify → Decom → Convert → Derive), the event accumulates data
  from each processing step.

  ## Design Principles

  - **Immutable accumulation**: Each stage adds data, never removes
  - **Stateless stages**: All state needed for processing is in the event
  - **Timing instrumentation**: Each stage records its processing time

  ## Example Flow

      # Created at PartitionRouter from PubSub message
      event = PipelineEvent.new(packet, metadata, mission_id)

      # After IdentifyStage
      event = %{event | packet_def: packet_def, packet_format: :ccsds}

      # After DecommutationStage
      event = %{event | raw_items: %{"cpu_temp" => 2456}}

      # After ConversionStage
      event = %{event | converted_items: %{"cpu_temp" => 25.6}}

      # After DeriveStage
      event = %{event | all_items: %{...}, items_with_limits: [...]}
  """

  alias Cadence.Telemetry.Packet

  @type t :: %__MODULE__{
          # Identity (set at creation, immutable)
          id: String.t(),
          mission_id: String.t(),
          target_id: String.t(),
          apid: non_neg_integer() | nil,
          partition: non_neg_integer(),

          # Source data
          packet: Packet.t(),
          metadata: map(),
          received_at: integer(),

          # Stage 1: Identify
          packet_def: map() | nil,
          packet_format: atom() | nil,

          # Stage 2: Decommutate
          raw_items: map() | nil,

          # Stage 3: Convert
          converted_items: map() | nil,
          qualified_items: map() | nil,

          # Stage 4: Derive
          all_items: map() | nil,
          items_with_limits: list() | nil,

          # Observability
          stage_timings: map()
        }

  defstruct [
    # Identity
    :id,
    :mission_id,
    :target_id,
    :apid,
    :partition,

    # Source data
    :packet,
    :metadata,
    :received_at,

    # Stage outputs
    :packet_def,
    :packet_format,
    :raw_items,
    :converted_items,
    :qualified_items,
    :all_items,
    :items_with_limits,

    # Observability
    stage_timings: %{}
  ]

  @doc """
  Creates a new PipelineEvent from a packet and metadata.

  Called by PartitionRouter when transforming PubSub messages.
  Computes the partition based on (target_id, apid) hash.

  ## Parameters

  - `packet` - The Packet struct from the interface
  - `metadata` - Interface metadata (target_id, received_at, etc.)
  - `mission_id` - Mission ID for this packet
  - `partition_count` - Number of partitions for routing

  ## Returns

  A new PipelineEvent struct ready for processing.
  """
  @spec new(Packet.t(), map(), String.t(), pos_integer()) :: t()
  def new(%Packet{} = packet, metadata, mission_id, partition_count) do
    target_id = metadata[:target_id] || packet.target_id || "default"
    apid = get_apid(packet)
    partition = compute_partition(target_id, apid, partition_count)

    %__MODULE__{
      id: generate_id(),
      mission_id: mission_id,
      target_id: target_id,
      apid: apid,
      partition: partition,
      packet: packet,
      metadata: metadata,
      received_at: System.monotonic_time(:microsecond),
      stage_timings: %{}
    }
  end

  @doc """
  Records timing for a stage.

  Call this after each stage completes processing to track latency.

  ## Parameters

  - `event` - The current PipelineEvent
  - `stage` - Atom identifying the stage (:identify, :decom, :convert, :derive)
  - `start_time` - Monotonic time in microseconds when stage started

  ## Returns

  Updated event with timing recorded.
  """
  @spec record_timing(t(), atom(), integer()) :: t()
  def record_timing(%__MODULE__{} = event, stage, start_time) do
    duration = System.monotonic_time(:microsecond) - start_time
    %{event | stage_timings: Map.put(event.stage_timings, stage, duration)}
  end

  @doc """
  Returns total processing time across all stages.
  """
  @spec total_processing_time(t()) :: integer()
  def total_processing_time(%__MODULE__{stage_timings: timings}) do
    timings
    |> Map.values()
    |> Enum.sum()
  end

  @doc """
  Returns the partition key tuple for this event.

  Used for debugging and observability.
  """
  @spec partition_key(t()) :: {String.t(), non_neg_integer() | nil}
  def partition_key(%__MODULE__{target_id: target_id, apid: apid}) do
    {target_id, apid}
  end

  # Private functions

  @spec compute_partition(String.t(), non_neg_integer() | nil, pos_integer()) :: non_neg_integer()
  defp compute_partition(target_id, apid, partition_count) do
    :erlang.phash2({target_id, apid}, partition_count)
  end

  @spec get_apid(Packet.t()) :: non_neg_integer() | nil
  defp get_apid(%Packet{ccsds_header: %{apid: apid}}) when not is_nil(apid), do: apid

  defp get_apid(%Packet{raw: raw}) when is_binary(raw) and byte_size(raw) > 0 do
    # For simulator format, use type byte as pseudo-APID
    <<type_byte::8, _rest::binary>> = raw
    type_byte
  end

  defp get_apid(_), do: nil

  @spec generate_id() :: String.t()
  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
