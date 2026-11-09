defmodule Cadence.Capabilities.TransportExtensions.UplinkGateway.Checkpoint do
  @moduledoc "Version 1 COP-1 state encoding. Restoration has no emission or timer effects."
  alias Cadence.Capabilities.ExecutionResult
  alias Cadence.Runtime.ProtocolCheckpoint.Data
  alias CCSDS.TC.TransferFrame
  alias CCSDS.Transport.COP1.FOP

  @dynamic_fields ~w(next_frame_seq packet_sequence_counts cop1 accepted_uplink_count
    started_uplink_count completed_uplink_count last_release_attempt_id last_command_request_id
    last_command_name last_signal_phase last_signal_at last_control_at active_releases)a

  def export(state, _context) do
    with :ok <- validate(state, state), {:ok, data} <- Data.encode(state) do
      {:ok, %{"schema_version" => 1, "implementation" => "cadence-cop1/v1", "state" => data}}
    end
  end

  def restore(
        %{"schema_version" => 1, "implementation" => "cadence-cop1/v1", "state" => data},
        fresh,
        _context
      ) do
    with {:ok, state} <- Data.decode(data), :ok <- validate(state, fresh) do
      {:ok, ExecutionResult.new(%{state: state})}
    end
  end

  def restore(_, _, _), do: {:error, :unsupported_protocol_checkpoint_version}

  defp validate(%{cop1_mode: :fop, cop1: %FOP{} = fop} = state, fresh) do
    {:ok, validated} = FOP.init(Map.from_struct(fop))

    valid =
      validated == fop and shape?(state, fresh) and configuration?(state, fop) and
        procedure?(state, fop) and counters?(state.packet_sequence_counts) and
        progress_counters?(state) and timestamps?(state) and frames?(state)

    if valid, do: :ok, else: {:error, :invalid_cop1_checkpoint}
  rescue
    _ -> {:error, :invalid_cop1_checkpoint}
  end

  defp validate(_, _), do: {:error, :unsupported_protocol_restoration}

  defp progress_counters?(state) do
    Enum.all?(
      [state.accepted_uplink_count, state.started_uplink_count, state.completed_uplink_count],
      &(is_integer(&1) and &1 >= 0)
    )
  end

  defp shape?(state, fresh) do
    MapSet.new(Map.keys(state)) == MapSet.new(Map.keys(fresh)) and
      Map.drop(state, @dynamic_fields) == Map.drop(fresh, @dynamic_fields) and
      state.transport_profile == :tc and state.bypass_flag == 0 and
      state.control_command_flag == 0
  end

  defp configuration?(state, fop) do
    fop.enabled and fop.vcid == state.vcid and state.next_frame_seq == fop.vs and
      fop.lower_layer_mode == :synchronous and fop.t1_initial_ms == state.cop1_timeout_ms and
      fop.transmission_limit == state.cop1_max_retransmit + 1 and
      fop.sliding_window_width == state.cop1_window_size and
      fop.timeout_type == state.cop1_timeout_type
  end

  defp procedure?(state, fop) do
    Enum.all?([fop.pending_directive, fop.pending_bd, fop.wait_queue], &is_nil/1) and
      Enum.all?(
        [
          fop.lockout,
          fop.wait,
          fop.retransmit,
          fop.ad_out_ready,
          fop.bc_out_ready,
          fop.bd_out_ready
        ],
        &is_boolean/1
      ) and
      (is_nil(fop.last_report_value) or
         (is_integer(fop.last_report_value) and fop.last_report_value in 0..255)) and
      fop.transmission_count <= fop.transmission_limit + 1 and state.active_releases == %{}
  end

  defp counters?(counts) when is_map(counts) do
    Enum.all?(counts, fn {apid, count} ->
      is_integer(apid) and apid in 0..2047 and
        is_integer(count) and count in 0..16_383
    end)
  end

  defp counters?(_), do: false

  defp timestamps?(state) do
    Enum.all?(
      [state.last_signal_at, state.last_control_at],
      &(is_nil(&1) or is_struct(&1, DateTime))
    ) and
      state.last_signal_phase in [nil, :acceptance, :start, :completion, :failure] and
      Enum.all?(
        [state.last_release_attempt_id, state.last_command_request_id, state.last_command_name],
        &(is_nil(&1) or is_binary(&1))
      )
  end

  defp frames?(%{cop1: fop} = state) do
    queue = fop.sent_queue
    distance = rem(fop.vs - fop.nnr + 256, 256)

    is_list(queue) and length(queue) == distance and distance <= fop.sliding_window_width and
      Enum.all?(Enum.with_index(queue), fn {entry, index} ->
        entry.frame_type == :ad and entry.control_command == nil and is_boolean(entry.retransmit?) and
          entry.frame.seq == rem(fop.nnr + index, 256) and frame?(entry.frame, state)
      end) and release?(fop.in_flight_release, queue)
  end

  defp frame?(frame, state) do
    with true <- is_integer(frame.retries) and frame.retries in 0..state.cop1_max_retransmit,
         {:ok, bytes} <- Base.decode64(frame.frame_base64),
         {:ok, [wire], <<>>} <-
           TransferFrame.decode(bytes, frame_size: state.frame_size, fecf: state.fecf) do
      wire.scid == state.scid and wire.vcid == state.vcid and wire.frame_seq == frame.seq and
        wire.bypass_flag == 0 and wire.control_command_flag == 0
    else
      _ -> false
    end
  end

  defp release?(nil, []), do: true

  defp release?(%{frames: frames, metadata: metadata, base_request: request}, queue) do
    frames == Enum.map(queue, & &1.frame) and is_map(metadata) and is_map(request) and
      is_binary(metadata[:command_release_attempt_id]) and
      is_binary(metadata[:command_request_id]) and
      metadata[:command_release_attempt_id] == request[:command_release_attempt_id] and
      metadata[:command_request_id] == request[:command_request_id] and
      Enum.all?(queue, &(&1.request == metadata))
  end

  defp release?(_, _), do: false
end
