defmodule Cadence.CCSDS.SDLP.AOS.Continuity do
  @moduledoc """
  Pure AOS Virtual Channel frame-count continuity state.

  Realtime and replay streams are tracked independently for each GVCID. When
  the Frame Count Cycle is managed as present, the 24-bit VCFC and four-bit
  cycle are treated as one 28-bit counter. OID frames use reserved VCID 63 and
  are deliberately excluded because AOS does not require their VCFC to be
  maintained.
  """

  alias Cadence.CCSDS.Core.LinkFrame

  @type counter_status :: :untracked | :first | :continuous | :duplicate | :discontinuity
  @type report :: %{
          status: counter_status(),
          previous: non_neg_integer() | nil,
          expected: non_neg_integer() | nil,
          observed: non_neg_integer(),
          modulus: 0x1000000 | 0x10000000,
          forward_distance: non_neg_integer(),
          loss?: boolean(),
          cycle_used?: boolean(),
          replay?: boolean(),
          anomalies: [map()]
        }

  @type key :: {binary(), 0, 0..1023, 0..62, 0 | 1}
  @type entry :: %{count: non_neg_integer(), cycle_used?: boolean()}
  @type t :: %__MODULE__{counts: %{optional(key()) => entry()}}

  defstruct counts: %{}

  @spec init() :: t()
  def init, do: %__MODULE__{}

  @spec observe(LinkFrame.t(), t()) :: {:ok, report(), t()} | {:error, term()}
  def observe(%LinkFrame{profile: :aos, vcid: 63} = frame, %__MODULE__{} = state) do
    with :ok <- validate_address(frame),
         {:ok, count, cycle_used?, replay?} <- observed_count(frame) do
      {:ok, report(:untracked, count, cycle_used?, %{replay?: replay?}), state}
    end
  end

  def observe(%LinkFrame{profile: :aos} = frame, %__MODULE__{} = state) do
    with :ok <- validate_address(frame),
         {:ok, count, cycle_used?, replay?} <- observed_count(frame) do
      key =
        {Map.get(frame.meta, :physical_channel, "default"), 0, frame.scid, frame.vcid,
         bool_bit(replay?)}

      previous = Map.get(state.counts, key)

      continuity =
        previous
        |> classify(count, cycle_used?)
        |> Map.put(:replay?, replay?)

      anomalies = anomalies(frame, continuity)

      next_state = %{
        state
        | counts: Map.put(state.counts, key, %{count: count, cycle_used?: cycle_used?})
      }

      {:ok, Map.put(continuity, :anomalies, anomalies), next_state}
    end
  end

  def observe(%LinkFrame{profile: profile}, %__MODULE__{}),
    do: {:error, {:invalid_profile, profile}}

  def observe(frame, state), do: {:error, {:invalid_continuity_input, frame, state}}

  @spec reset_virtual_channel(t(), 0..1023, 0..62) :: t()
  def reset_virtual_channel(%__MODULE__{} = state, scid, vcid) do
    counts =
      Map.reject(state.counts, fn
        {{_physical_channel, 0, ^scid, ^vcid, _replay}, _entry} -> true
        {_key, _entry} -> false
      end)

    %{state | counts: counts}
  end

  @spec reset_master_channel(t(), 0..1023) :: t()
  def reset_master_channel(%__MODULE__{} = state, scid) do
    counts =
      Map.reject(state.counts, fn
        {{_physical_channel, 0, ^scid, _vcid, _replay}, _entry} -> true
        {_key, _entry} -> false
      end)

    %{state | counts: counts}
  end

  defp observed_count(frame) do
    vcfc = Map.get(frame.meta, :vcfc, frame.frame_seq)
    cycle_use = Map.get(frame.meta, :vc_frame_count_cycle_use_flag, 0)
    cycle = Map.get(frame.meta, :vc_frame_count_cycle, 0)
    replay = Map.get(frame.meta, :replay_flag, 0)

    with :ok <- validate_range(vcfc, 0, 0xFFFFFF, :vcfc),
         :ok <- validate_bit(cycle_use, :vc_frame_count_cycle_use_flag),
         :ok <- validate_cycle(cycle, cycle_use),
         :ok <- validate_bit(replay, :replay_flag) do
      cycle_used? = cycle_use == 1
      count = if(cycle_used?, do: cycle * 0x1000000 + vcfc, else: vcfc)
      {:ok, count, cycle_used?, replay == 1}
    end
  end

  defp classify(nil, observed, cycle_used?) do
    report(:first, observed, cycle_used?)
  end

  defp classify(%{count: previous, cycle_used?: previous_mode}, observed, cycle_used?)
       when previous_mode != cycle_used? do
    report(:discontinuity, observed, cycle_used?, %{
      previous: previous,
      loss?: true,
      mode_changed?: true
    })
  end

  defp classify(%{count: previous}, observed, cycle_used?) do
    modulus = modulus(cycle_used?)
    expected = Integer.mod(previous + 1, modulus)
    forward_distance = Integer.mod(observed - expected, modulus)

    status =
      cond do
        observed == expected -> :continuous
        observed == previous -> :duplicate
        true -> :discontinuity
      end

    report(status, observed, cycle_used?, %{
      previous: previous,
      expected: expected,
      modulus: modulus,
      forward_distance: forward_distance,
      loss?: status not in [:first, :continuous]
    })
  end

  defp report(status, observed, cycle_used?, overrides \\ %{}) do
    Map.merge(
      %{
        status: status,
        previous: nil,
        expected: nil,
        observed: observed,
        modulus: modulus(cycle_used?),
        forward_distance: 0,
        loss?: false,
        cycle_used?: cycle_used?,
        replay?: false,
        anomalies: []
      },
      overrides
    )
  end

  defp anomalies(_frame, %{loss?: false}), do: []

  defp anomalies(frame, continuity) do
    [
      %{
        anomaly_kind: :virtual_channel_frame_count_discontinuity,
        scid: frame.scid,
        vcid: frame.vcid,
        frame_seq: frame.frame_seq,
        metadata: continuity
      }
    ]
  end

  defp validate_address(%LinkFrame{scid: scid, vcid: vcid})
       when is_integer(scid) and scid in 0..1023 and is_integer(vcid) and vcid in 0..63,
       do: :ok

  defp validate_address(frame), do: {:error, {:invalid_aos_address, frame.scid, frame.vcid}}

  defp validate_cycle(0, 0), do: :ok
  defp validate_cycle(value, 0), do: {:error, {:unused_aos_frame_count_cycle_not_zero, value}}
  defp validate_cycle(value, 1) when is_integer(value) and value in 0..15, do: :ok
  defp validate_cycle(value, flag), do: {:error, {:invalid_aos_frame_count_cycle, value, flag}}

  defp validate_bit(value, _field) when value in [0, 1], do: :ok
  defp validate_bit(value, field), do: {:error, {:invalid_field, field, value}}

  defp validate_range(value, minimum, maximum, _field)
       when is_integer(value) and value >= minimum and value <= maximum,
       do: :ok

  defp validate_range(value, _minimum, _maximum, field),
    do: {:error, {:invalid_field, field, value}}

  defp modulus(true), do: 0x10000000
  defp modulus(false), do: 0x1000000
  defp bool_bit(true), do: 1
  defp bool_bit(false), do: 0
end
