defmodule Cadence.CCSDS.SDLP.TM.Continuity do
  @moduledoc """
  Pure TM Master- and Virtual-Channel frame-count continuity state.

  Master Channel Frame Counts are tracked independently per MCID and Virtual
  Channel Frame Counts independently per GVCID. An observation returns both a
  structured report and protocol-native anomaly evidence; callers decide how
  and where that evidence is persisted.
  """

  alias Cadence.CCSDS.Core.LinkFrame

  @type counter_status :: :first | :continuous | :duplicate | :discontinuity
  @type counter_report :: %{
          status: counter_status(),
          previous: 0..255 | nil,
          expected: 0..255 | nil,
          observed: 0..255,
          forward_distance: 0..255,
          loss?: boolean()
        }

  @type report :: %{
          master_channel: counter_report(),
          virtual_channel: counter_report(),
          anomalies: [map()]
        }

  @type t :: %__MODULE__{
          master_counts: %{optional({0, 0..1023}) => 0..255},
          virtual_counts: %{optional({0, 0..1023, 0..7}) => 0..255}
        }

  defstruct master_counts: %{}, virtual_counts: %{}

  @spec init() :: t()
  def init, do: %__MODULE__{}

  @spec observe(LinkFrame.t(), t()) :: {:ok, report(), t()} | {:error, term()}
  def observe(%LinkFrame{profile: :tm} = frame, %__MODULE__{} = state) do
    mcfc = Map.get(frame.meta, :mcfc, frame.frame_seq)
    vcfc = Map.get(frame.meta, :vcfc, frame.frame_seq)

    with :ok <- validate_counter(mcfc, :mcfc),
         :ok <- validate_counter(vcfc, :vcfc),
         :ok <- validate_address(frame) do
      master_key = {0, frame.scid}
      virtual_key = {0, frame.scid, frame.vcid}
      master_report = classify(Map.get(state.master_counts, master_key), mcfc)
      virtual_report = classify(Map.get(state.virtual_counts, virtual_key), vcfc)

      report = %{
        master_channel: master_report,
        virtual_channel: virtual_report,
        anomalies:
          anomalies(frame, :master_channel, master_report) ++
            anomalies(frame, :virtual_channel, virtual_report)
      }

      next_state = %{
        state
        | master_counts: Map.put(state.master_counts, master_key, mcfc),
          virtual_counts: Map.put(state.virtual_counts, virtual_key, vcfc)
      }

      {:ok, report, next_state}
    end
  end

  def observe(%LinkFrame{profile: profile}, %__MODULE__{}),
    do: {:error, {:invalid_profile, profile}}

  def observe(frame, state), do: {:error, {:invalid_continuity_input, frame, state}}

  @spec reset_virtual_channel(t(), 0..1023, 0..7) :: t()
  def reset_virtual_channel(%__MODULE__{} = state, scid, vcid) do
    %{state | virtual_counts: Map.delete(state.virtual_counts, {0, scid, vcid})}
  end

  @spec reset_master_channel(t(), 0..1023) :: t()
  def reset_master_channel(%__MODULE__{} = state, scid) do
    virtual_counts =
      Map.reject(state.virtual_counts, fn
        {{0, ^scid, _vcid}, _count} -> true
        {_key, _count} -> false
      end)

    %{
      state
      | master_counts: Map.delete(state.master_counts, {0, scid}),
        virtual_counts: virtual_counts
    }
  end

  defp classify(nil, observed) do
    %{
      status: :first,
      previous: nil,
      expected: nil,
      observed: observed,
      forward_distance: 0,
      loss?: false
    }
  end

  defp classify(previous, observed) do
    expected = increment(previous)
    forward_distance = Integer.mod(observed - expected, 256)

    status =
      cond do
        observed == expected -> :continuous
        observed == previous -> :duplicate
        true -> :discontinuity
      end

    %{
      status: status,
      previous: previous,
      expected: expected,
      observed: observed,
      forward_distance: forward_distance,
      loss?: status not in [:first, :continuous]
    }
  end

  defp anomalies(_frame, _channel, %{loss?: false}), do: []

  defp anomalies(frame, channel, report) do
    [
      %{
        anomaly_kind: anomaly_kind(channel),
        scid: frame.scid,
        vcid: if(channel == :virtual_channel, do: frame.vcid, else: nil),
        frame_seq: frame.frame_seq,
        metadata: Map.put(report, :channel, channel)
      }
    ]
  end

  defp anomaly_kind(:master_channel), do: :master_channel_frame_count_discontinuity
  defp anomaly_kind(:virtual_channel), do: :virtual_channel_frame_count_discontinuity

  defp validate_counter(value, _field) when is_integer(value) and value in 0..255, do: :ok
  defp validate_counter(value, field), do: {:error, {:invalid_counter, field, value}}

  defp validate_address(%LinkFrame{scid: scid, vcid: vcid})
       when is_integer(scid) and scid in 0..1023 and is_integer(vcid) and vcid in 0..7,
       do: :ok

  defp validate_address(frame), do: {:error, {:invalid_tm_address, frame.scid, frame.vcid}}

  defp increment(value), do: Integer.mod(value + 1, 256)
end
