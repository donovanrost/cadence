defmodule CCSDS.SDLP.USLP.Continuity do
  @moduledoc """
  Pure USLP Virtual Channel continuity state.

  Sequence-Controlled and Expedited frames have independent counters and may
  use different managed widths. Truncated and OID frames do not carry a count
  and are reported as untracked.
  """

  alias CCSDS.Core.LinkFrame

  @type status :: :untracked | :first | :continuous | :duplicate | :discontinuity
  @type report :: %{
          status: status(),
          previous: non_neg_integer() | nil,
          expected: non_neg_integer() | nil,
          observed: non_neg_integer() | nil,
          count_octets: 0..7,
          modulus: pos_integer() | nil,
          forward_distance: non_neg_integer(),
          loss?: boolean(),
          qos: :sequence_controlled | :expedited,
          anomalies: [map()]
        }
  @type key :: {binary(), 0..65_535, 0..62, :sequence_controlled | :expedited}
  @type t :: %__MODULE__{
          counts: %{optional(key()) => %{count: non_neg_integer(), count_octets: 1..7}}
        }

  defstruct counts: %{}

  @spec init() :: t()
  def init, do: %__MODULE__{}

  @spec observe(LinkFrame.t(), t()) :: {:ok, report(), t()} | {:error, term()}
  def observe(%LinkFrame{profile: :uslp} = frame, %__MODULE__{} = state) do
    with :ok <- validate_address(frame),
         {:ok, qos} <- qos(frame),
         {:ok, count, count_octets} <- observed_count(frame) do
      observe_count(frame, qos, count, count_octets, state)
    end
  end

  def observe(%LinkFrame{profile: profile}, %__MODULE__{}),
    do: {:error, {:invalid_profile, profile}}

  def observe(frame, state), do: {:error, {:invalid_continuity_input, frame, state}}

  @spec reset_virtual_channel(t(), 0..65_535, 0..62) :: t()
  def reset_virtual_channel(%__MODULE__{} = state, scid, vcid) do
    counts =
      Map.reject(state.counts, fn
        {{_physical_channel, ^scid, ^vcid, _qos}, _entry} -> true
        {_key, _entry} -> false
      end)

    %{state | counts: counts}
  end

  defp observe_count(_frame, qos, nil, 0, state) do
    {:ok, report(:untracked, nil, 0, qos), state}
  end

  defp observe_count(%LinkFrame{vcid: 63}, qos, count, count_octets, state) do
    {:ok, report(:untracked, count, count_octets, qos), state}
  end

  defp observe_count(frame, qos, count, count_octets, state) do
    key = {Map.get(frame.meta, :physical_channel, "default"), frame.scid, frame.vcid, qos}
    previous = Map.get(state.counts, key)
    continuity = classify(previous, count, count_octets, qos)
    anomalies = anomalies(frame, continuity)

    next_state = %{
      state
      | counts: Map.put(state.counts, key, %{count: count, count_octets: count_octets})
    }

    {:ok, Map.put(continuity, :anomalies, anomalies), next_state}
  end

  defp classify(nil, observed, count_octets, qos),
    do: report(:first, observed, count_octets, qos)

  defp classify(%{count_octets: previous_octets, count: previous}, observed, count_octets, qos)
       when previous_octets != count_octets do
    report(:discontinuity, observed, count_octets, qos, %{
      previous: previous,
      loss?: true,
      count_width_changed?: true
    })
  end

  defp classify(%{count: previous}, observed, count_octets, qos) do
    modulus = modulus(count_octets)
    expected = Integer.mod(previous + 1, modulus)
    distance = Integer.mod(observed - expected, modulus)

    status =
      cond do
        observed == expected -> :continuous
        observed == previous -> :duplicate
        true -> :discontinuity
      end

    report(status, observed, count_octets, qos, %{
      previous: previous,
      expected: expected,
      forward_distance: distance,
      loss?: status not in [:first, :continuous]
    })
  end

  defp report(status, observed, count_octets, qos, overrides \\ %{}) do
    Map.merge(
      %{
        status: status,
        previous: nil,
        expected: nil,
        observed: observed,
        count_octets: count_octets,
        modulus: if(count_octets == 0, do: nil, else: modulus(count_octets)),
        forward_distance: 0,
        loss?: false,
        qos: qos,
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

  defp observed_count(frame) do
    count = Map.get(frame.meta, :vcf_count, frame.frame_seq)
    count_octets = Map.get(frame.meta, :vcf_count_length, if(is_nil(count), do: 0, else: 1))

    validate_observed_count(count, count_octets)
  end

  defp validate_observed_count(nil, 0), do: {:ok, nil, 0}

  defp validate_observed_count(_count, count_octets)
       when not is_integer(count_octets) or count_octets not in 0..7,
       do: {:error, {:invalid_field, :vcf_count_length, count_octets}}

  defp validate_observed_count(count, count_octets) do
    if is_integer(count) and count >= 0 and count < Integer.pow(256, count_octets),
      do: {:ok, count, count_octets},
      else: {:error, {:invalid_uslp_frame_count, count, count_octets}}
  end

  defp qos(frame) do
    case Map.get(frame.meta, :qos) do
      value when value in [:sequence_controlled, :expedited] -> {:ok, value}
      value -> {:error, {:invalid_uslp_qos, value}}
    end
  end

  defp validate_address(%LinkFrame{scid: scid, vcid: vcid})
       when is_integer(scid) and scid in 0..65_535 and is_integer(vcid) and vcid in 0..63,
       do: :ok

  defp validate_address(frame), do: {:error, {:invalid_uslp_address, frame.scid, frame.vcid}}
  defp modulus(count_octets), do: Integer.pow(256, count_octets)
end
