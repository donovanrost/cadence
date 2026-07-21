defmodule CadenceSimulator.TMFramePlan do
  @moduledoc """
  Parallel-friendly TM frame planning.

  Workers can segment packets and build fixed payload/FHP plans in parallel,
  while the coordinator keeps final frame sequence assignment and ordered
  emission.
  """

  alias Cadence.CCSDS.FrameErrorControl
  alias Cadence.CCSDS.SpacePacket.Idle

  @primary_header_size 6
  @min_idle_packet_size 7

  @type plan :: %{payload: binary(), fhp: non_neg_integer()}
  @type cache :: %{optional(pos_integer()) => binary()}

  @spec plan(binary(), %{frame_size: pos_integer()}, cache()) ::
          {:ok, [plan()], cache()} | {:error, term(), cache()}
  def plan(packet, %{frame_size: frame_size} = frame, cache \\ %{})
      when is_binary(packet) and is_integer(frame_size) and frame_size > @primary_header_size do
    fecf_size = if Map.get(frame, :fecf, false), do: FrameErrorControl.size(), else: 0
    max_payload = frame_size - @primary_header_size - fecf_size

    if max_payload > 0 do
      {:ok, plans, next_cache} = build_plans(packet, max_payload, cache, [], true)
      {:ok, plans, next_cache}
    else
      {:error, :frame_size_too_small, cache}
    end
  end

  @spec encode_many([plan()], %{scid: non_neg_integer(), vcid: non_neg_integer()}, map()) ::
          {iodata(), non_neg_integer(), map()}
  def encode_many(
        plans,
        %{scid: scid, vcid: vcid} = frame_config,
        %{mcfc: mcfc, vcfc: vcfc} = state
      )
      when is_list(plans) do
    counter_step = Map.get(state, :counter_step, 1)
    fecf? = Map.get(frame_config, :fecf, false)

    {frames, _frame_count, next_mcfc, next_vcfc} =
      Enum.reduce(plans, {[], 0, mcfc, vcfc}, fn %{payload: payload, fhp: fhp},
                                                 {frames_acc, count, current_mcfc, current_vcfc} ->
        frame_without_fecf =
          <<
            0::2,
            scid::10,
            vcid::3,
            0::1,
            current_mcfc::8,
            current_vcfc::8,
            0::1,
            0::1,
            0::1,
            3::2,
            fhp::11,
            payload::binary
          >>

        frame =
          if fecf?, do: FrameErrorControl.append(frame_without_fecf), else: frame_without_fecf

        {
          [frame | frames_acc],
          count + 1,
          increment_counter(current_mcfc, counter_step),
          increment_counter(current_vcfc, counter_step)
        }
      end)

    reversed_frames = Enum.reverse(frames)

    {
      reversed_frames,
      Enum.reduce(reversed_frames, 0, fn frame, acc -> acc + byte_size(frame) end),
      %{state | mcfc: next_mcfc, vcfc: next_vcfc}
    }
  end

  defp build_plans(packet, max_payload, cache, acc, first?)
       when byte_size(packet) > max_payload do
    <<segment::binary-size(^max_payload), rest::binary>> = packet
    fhp = if first?, do: 0, else: 2047
    build_plans(rest, max_payload, cache, [%{payload: segment, fhp: fhp} | acc], false)
  end

  defp build_plans(packet, max_payload, cache, acc, first?) do
    {payload, next_cache} = build_last_payload(packet, max_payload, cache)
    fhp = if first?, do: 0, else: 2047
    {:ok, Enum.reverse([%{payload: payload, fhp: fhp} | acc]), next_cache}
  end

  defp build_last_payload(segment, max_payload, cache) do
    padding_size = max_payload - byte_size(segment)

    case build_idle_padding(padding_size, cache) do
      {<<>>, next_cache} -> {segment, next_cache}
      {padding, next_cache} -> {segment <> padding, next_cache}
    end
  end

  defp build_idle_padding(0, cache), do: {<<>>, cache}

  defp build_idle_padding(padding_size, _cache) when padding_size < @min_idle_packet_size do
    raise ArgumentError, "TM frame padding #{padding_size} bytes is too small for an idle packet"
  end

  defp build_idle_padding(padding_size, cache) do
    case cache do
      %{^padding_size => padding} ->
        {padding, cache}

      _ ->
        padding = Idle.encode!(padding_size)
        {padding, Map.put(cache, padding_size, padding)}
    end
  end

  defp increment_counter(value, step), do: rem(value + step, 256)
end
