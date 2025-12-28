defmodule Cadence.Simulator.GeneratorWorker do
  @moduledoc """
  Parallel telemetry generation worker.

  Each GeneratorWorker handles value generation and encoding for assigned steps,
  working in parallel with other workers. The worker:

  1. Receives step assignments from the Coordinator
  2. Generates values using the configured provider
  3. Encodes packets using shared encoder state
  4. Allocates sequence numbers via SequenceAllocator (lock-free)
  5. Sends encoded packets to SendBuffer (non-blocking)

  ## Usage

  Workers are spawned and managed by the Coordinator when running in parallel mode.

      {:ok, worker} = GeneratorWorker.start_link(
        worker_id: 0,
        provider_module: BasicDynamics,
        provider_state: provider_state,
        encoder: encoder,
        target_id: "SIM-1",
        sequence_allocator: allocator,
        send_buffer: send_buffer_pid
      )

      # Coordinator dispatches steps
      GeneratorWorker.generate(worker, step)
  """

  use GenServer
  require Logger

  alias Cadence.Simulator.{PacketEncoder, SendBuffer, SequenceAllocator, SimulatorMetrics}

  defstruct [
    :worker_id,
    :coordinator_id,
    :provider_module,
    :provider_state,
    :encoder,
    :target_id,
    :sequence_allocator,
    :send_buffer,
    :sample_rate
  ]

  @default_sample_rate 100

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Starts a generator worker.

  ## Options

  - `:worker_id` - Worker identifier (required)
  - `:coordinator_id` - ID for metrics tracking
  - `:provider_module` - Provider module (e.g., BasicDynamics)
  - `:provider_state` - Initial provider state
  - `:encoder` - PacketEncoder struct
  - `:target_id` - Target identifier
  - `:sequence_allocator` - SequenceAllocator struct
  - `:send_buffer` - SendBuffer PID
  - `:sample_rate` - Timing sample rate (default: 100)
  """
  def start_link(opts) do
    worker_id = Keyword.fetch!(opts, :worker_id)

    name =
      Keyword.get(
        opts,
        :name,
        {:via, Registry, {Cadence.MissionRegistry, {:generator_worker, worker_id}}}
      )

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Dispatches a step to the worker for generation. Non-blocking cast.

  The worker will generate values for this step, encode them, and send
  to the SendBuffer.
  """
  @spec generate(GenServer.server(), non_neg_integer()) :: :ok
  def generate(pid, step) when is_integer(step) do
    GenServer.cast(pid, {:generate, step})
  end

  @doc """
  Synchronous generation for testing. Blocks until complete.
  """
  @spec generate_sync(GenServer.server(), non_neg_integer()) :: :ok | {:error, term()}
  def generate_sync(pid, step) when is_integer(step) do
    GenServer.call(pid, {:generate, step})
  end

  @doc """
  Gets worker statistics.
  """
  @spec stats(GenServer.server()) :: map()
  def stats(pid) do
    GenServer.call(pid, :stats)
  end

  @doc """
  Stops the worker.
  """
  @spec stop(GenServer.server()) :: :ok
  def stop(pid) do
    GenServer.stop(pid)
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    worker_id = Keyword.fetch!(opts, :worker_id)
    coordinator_id = Keyword.get(opts, :coordinator_id, :default)
    provider_module = Keyword.fetch!(opts, :provider_module)
    provider_state = Keyword.fetch!(opts, :provider_state)
    encoder = Keyword.get(opts, :encoder)
    target_id = Keyword.fetch!(opts, :target_id)
    sequence_allocator = Keyword.fetch!(opts, :sequence_allocator)
    send_buffer = Keyword.fetch!(opts, :send_buffer)
    sample_rate = Keyword.get(opts, :sample_rate, @default_sample_rate)

    state = %__MODULE__{
      worker_id: worker_id,
      coordinator_id: coordinator_id,
      provider_module: provider_module,
      provider_state: provider_state,
      encoder: encoder,
      target_id: target_id,
      sequence_allocator: sequence_allocator,
      send_buffer: send_buffer,
      sample_rate: sample_rate
    }

    Logger.debug("GeneratorWorker #{worker_id} started")

    {:ok, state}
  end

  @impl true
  def handle_cast({:generate, step}, state) do
    do_generate(state, step)
    {:noreply, state}
  end

  @impl true
  def handle_call({:generate, step}, _from, state) do
    result = do_generate(state, step)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      worker_id: state.worker_id,
      provider: state.provider_module,
      target_id: state.target_id,
      has_encoder: state.encoder != nil
    }

    {:reply, stats, state}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp do_generate(state, step) do
    %{
      provider_module: provider_module,
      provider_state: provider_state,
      encoder: encoder,
      target_id: target_id,
      sequence_allocator: sequence_allocator,
      send_buffer: send_buffer,
      coordinator_id: coordinator_id,
      sample_rate: sample_rate
    } = state

    # Sample timing
    should_time = rem(step, sample_rate) == 0
    start_time = if should_time, do: System.monotonic_time(:microsecond)

    # Generate values from provider
    case provider_module.generate_values(provider_state, step) do
      {:ok, values, _new_provider_state} ->
        if should_time do
          gen_time = System.monotonic_time(:microsecond) - start_time
          SimulatorMetrics.record_timing(coordinator_id, :generation, gen_time)
        end

        SimulatorMetrics.inc(coordinator_id, :packets_generated)

        # Encode and send
        encode_start = if should_time, do: System.monotonic_time(:microsecond)
        encode_and_send(encoder, target_id, values, sequence_allocator, send_buffer)

        if should_time do
          encode_time = System.monotonic_time(:microsecond) - encode_start
          SimulatorMetrics.record_timing(coordinator_id, :encoding, encode_time)
        end

        :ok

      {:error, reason, _new_provider_state} ->
        Logger.warning(
          "GeneratorWorker #{state.worker_id} generation error at step #{step}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp encode_and_send(nil, target_id, values, _sequence_allocator, send_buffer) do
    # No encoder - use hardcoded legacy encoding
    packets = encode_hardcoded(target_id, values)

    Enum.each(packets, fn binary ->
      SendBuffer.send_packet(send_buffer, binary)
    end)
  end

  defp encode_and_send(encoder, target_id, values, sequence_allocator, send_buffer) do
    # Use encoder with external sequence allocation
    sequence_fn = fn apid ->
      SequenceAllocator.next(sequence_allocator, apid)
    end

    {:ok, packets} = PacketEncoder.encode_with_sequence(encoder, target_id, values, sequence_fn)

    Enum.each(packets, fn {_packet_name, binary} ->
      SendBuffer.send_packet(send_buffer, binary)
    end)
  end

  # Hardcoded encoding for when no encoder is provided (legacy behavior)
  defp encode_hardcoded(target_id, values) do
    import Bitwise

    # Group by packet
    by_packet =
      Enum.group_by(values, fn {qualified_name, _} ->
        case String.split(qualified_name, ".", parts: 2) do
          [packet_name, _] -> packet_name
          _ -> "UNKNOWN"
        end
      end)

    sync = <<0x1A, 0xCF, 0xFC, 0x1D>>

    Enum.flat_map(by_packet, fn {packet_name, items} ->
      item_values =
        Enum.into(items, %{}, fn {qualified, value} ->
          [_, item] = String.split(qualified, ".", parts: 2)
          {item, value}
        end)

      case encode_legacy_packet(packet_name, target_id, item_values, sync) do
        nil -> []
        binary -> [binary]
      end
    end)
  end

  defp encode_legacy_packet("HEALTH", target_id, data, sync) do
    import Bitwise

    timestamp = System.system_time(:second)
    target_hash = :erlang.phash2(target_id, 65_536)
    secondary_header = <<timestamp::48, target_hash::16>>

    cpu_temp = Map.get(data, "cpu_temp", 25.0)
    battery_voltage = Map.get(data, "battery_voltage", 14.5)
    battery_current = Map.get(data, "battery_current", 2.3)
    battery_percentage = Map.get(data, "battery_percentage", 75.0)
    uptime = Map.get(data, "uptime_seconds", 0)
    memory = Map.get(data, "memory_used_mb", 512)

    user_data = <<
      cpu_temp::float-32,
      battery_voltage::float-32,
      battery_current::float-32,
      trunc(battery_percentage)::8,
      uptime::32,
      memory::16
    >>

    payload = secondary_header <> user_data
    build_ccsds(100, 0, payload, sync)
  end

  defp encode_legacy_packet("ATTITUDE", target_id, data, sync) do
    import Bitwise

    timestamp = System.system_time(:second)
    target_hash = :erlang.phash2(target_id, 65_536)
    secondary_header = <<timestamp::48, target_hash::16>>

    roll = Map.get(data, "roll", 0.0)
    pitch = Map.get(data, "pitch", 0.0)
    yaw = Map.get(data, "yaw", 0.0)
    roll_rate = Map.get(data, "roll_rate", 0.0)
    pitch_rate = Map.get(data, "pitch_rate", 0.0)
    yaw_rate = Map.get(data, "yaw_rate", 0.0)

    user_data = <<
      roll::float-32,
      pitch::float-32,
      yaw::float-32,
      roll_rate::float-32,
      pitch_rate::float-32,
      yaw_rate::float-32
    >>

    payload = secondary_header <> user_data
    build_ccsds(101, 0, payload, sync)
  end

  defp encode_legacy_packet("POWER", target_id, data, sync) do
    import Bitwise

    timestamp = System.system_time(:second)
    target_hash = :erlang.phash2(target_id, 65_536)
    secondary_header = <<timestamp::48, target_hash::16>>

    solar_voltage = Map.get(data, "solar_panel_voltage", 28.0)
    solar_current = Map.get(data, "solar_panel_current", 5.0)
    bus_voltage = Map.get(data, "bus_voltage", 27.5)
    bus_current = Map.get(data, "bus_current", 3.2)

    power_mode =
      case Map.get(data, "power_mode", "NOMINAL") do
        "NOMINAL" -> 0
        "BATTERY" -> 1
        "CHARGING" -> 2
        _ -> 255
      end

    user_data = <<
      solar_voltage::float-32,
      solar_current::float-32,
      bus_voltage::float-32,
      bus_current::float-32,
      power_mode::8
    >>

    payload = secondary_header <> user_data
    build_ccsds(102, 0, payload, sync)
  end

  defp encode_legacy_packet(_packet_name, _target_id, _data, _sync), do: nil

  defp build_ccsds(apid, sequence, payload, sync) do
    import Bitwise

    version = 0
    type = 0
    sec_hdr_flag = 1
    packet_id = version <<< 13 ||| type <<< 12 ||| sec_hdr_flag <<< 11 ||| apid

    sequence_flags = 3
    seq_control = sequence_flags <<< 14 ||| sequence

    data_length = byte_size(payload) - 1

    primary_header = <<packet_id::16, seq_control::16, data_length::16>>

    sync <> primary_header <> payload
  end
end
