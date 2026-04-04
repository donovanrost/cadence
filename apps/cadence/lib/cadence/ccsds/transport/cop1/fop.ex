defmodule Cadence.CCSDS.Transport.COP1.FOP do
  @moduledoc """
  Small pure COP-1 FOP state machine for one uplink transport lane.

  This keeps the current implementation focused on a single in-flight command
  release while still driving start, retransmit, and completion from real CLCW
  state rather than simulated transport timers.
  """

  alias Cadence.CCSDS.Transport.COP1.CLCW

  @type frame_entry :: %{
          seq: non_neg_integer(),
          frame_base64: binary(),
          retries: non_neg_integer()
        }

  @type release_metadata :: %{
          command_release_attempt_id: binary(),
          command_request_id: binary(),
          command_name: binary() | nil,
          source_endpoint_ref: binary() | nil
        }

  @type release :: %{
          metadata: release_metadata(),
          base_request: term(),
          frames: [frame_entry()]
        }

  @type transition :: %{
          state: t(),
          transmit_frames: [frame_entry()],
          schedule_timeout_seqs: [non_neg_integer()],
          cancel_timeout_seqs: [non_neg_integer()],
          signal: {:start | :completion, release_metadata()} | nil
        }

  @type t :: %__MODULE__{
          enabled: boolean(),
          vcid: non_neg_integer() | nil,
          timeout_ms: pos_integer(),
          max_retransmit: non_neg_integer(),
          in_flight_release: release() | nil,
          lockout: boolean(),
          wait: boolean(),
          retransmit: boolean(),
          last_report_value: non_neg_integer() | nil
        }

  defstruct enabled: false,
            vcid: nil,
            timeout_ms: 5_000,
            max_retransmit: 3,
            in_flight_release: nil,
            lockout: false,
            wait: false,
            retransmit: false,
            last_report_value: nil

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    struct(__MODULE__, attrs)
  end

  @spec accept_release(t(), term(), [frame_entry()]) :: {:ok, transition()} | {:error, term()}
  def accept_release(%__MODULE__{enabled: false}, _base_request, _frames),
    do: {:error, :cop1_disabled}

  def accept_release(%__MODULE__{lockout: true}, _base_request, _frames),
    do: {:error, :lockout}

  def accept_release(%__MODULE__{wait: true}, _base_request, _frames),
    do: {:error, :cop1_wait}

  def accept_release(%__MODULE__{in_flight_release: %{}}, _base_request, _frames),
    do: {:error, :cop1_window_full}

  def accept_release(%__MODULE__{} = _state, _base_request, []),
    do: {:error, :empty_cop1_release}

  def accept_release(%__MODULE__{} = state, base_request, frames) when is_list(frames) do
    release = %{
      metadata: release_metadata(base_request),
      base_request: base_request,
      frames: Enum.map(frames, &Map.put(&1, :retries, 0))
    }

    {:ok,
     %{
       state: %{state | in_flight_release: release},
       transmit_frames: release.frames,
       schedule_timeout_seqs: Enum.map(release.frames, & &1.seq),
       cancel_timeout_seqs: [],
       signal: {:start, release.metadata}
     }}
  end

  @spec apply_clcw(t(), CLCW.t()) :: {:ok, transition()}
  def apply_clcw(%__MODULE__{} = state, %CLCW{} = clcw) do
    if vcid_mismatch?(state, clcw) do
      {:ok, no_op(state)}
    else
      state = update_flags(state, clcw)

      transition =
        if state.lockout do
          cancel_timeout_seqs =
            current_release_frame_seqs(state.in_flight_release)

          %{
            state: %{state | in_flight_release: nil},
            transmit_frames: [],
            schedule_timeout_seqs: [],
            cancel_timeout_seqs: cancel_timeout_seqs,
            signal: nil
          }
        else
          state
          |> apply_report_value(clcw.report_value)
          |> maybe_retransmit(clcw)
        end

      {:ok, transition}
    end
  end

  @spec handle_timeout(t(), non_neg_integer()) :: {:ok, transition()}
  def handle_timeout(%__MODULE__{} = state, seq) when is_integer(seq) and seq >= 0 do
    case state.in_flight_release do
      nil ->
        {:ok, no_op(state)}

      %{frames: frames} = release ->
        handle_release_timeout(state, release, frames, seq)
    end
  end

  defp no_op(state) do
    %{
      state: state,
      transmit_frames: [],
      schedule_timeout_seqs: [],
      cancel_timeout_seqs: [],
      signal: nil
    }
  end

  defp apply_report_value(%__MODULE__{} = state, report_value) do
    case state.in_flight_release do
      nil ->
        %{no_op(state) | state: %{state | last_report_value: report_value}}

      %{frames: []} ->
        %{
          no_op(state)
          | state: %{state | in_flight_release: nil, last_report_value: report_value}
        }

      %{frames: frames} = release ->
        if valid_report_value?(state, report_value) do
          apply_valid_report_value(state, release, frames, report_value)
        else
          no_op(state)
        end
    end
  end

  defp maybe_retransmit(
         %{
           state:
             %__MODULE__{retransmit: true, in_flight_release: %{frames: frames} = release} =
               state
         } = transition,
         %CLCW{}
       )
       when length(frames) > 0 do
    if Enum.any?(frames, &(&1.retries >= state.max_retransmit)) do
      %{
        transition
        | state: %{state | lockout: true, in_flight_release: nil},
          cancel_timeout_seqs:
            Enum.uniq(transition.cancel_timeout_seqs ++ Enum.map(frames, & &1.seq))
      }
    else
      retransmitted_frames =
        Enum.map(frames, &Map.update!(&1, :retries, fn retries -> retries + 1 end))

      %{
        transition
        | state: %{state | in_flight_release: %{release | frames: retransmitted_frames}},
          transmit_frames: transition.transmit_frames ++ retransmitted_frames,
          schedule_timeout_seqs:
            Enum.uniq(
              transition.schedule_timeout_seqs ++ Enum.map(retransmitted_frames, & &1.seq)
            )
      }
    end
  end

  defp maybe_retransmit(transition, %CLCW{}), do: transition

  defp release_metadata(base_request) do
    %{
      command_release_attempt_id: Map.fetch!(base_request, :command_release_attempt_id),
      command_request_id: Map.fetch!(base_request, :command_request_id),
      command_name: Map.get(base_request, :command_name),
      source_endpoint_ref: Map.get(base_request, :source_endpoint_ref)
    }
  end

  defp update_release_frame_retry(%{frames: frames} = release, seq) do
    updated_frames = Enum.map(frames, &increment_frame_retry(&1, seq))

    %{release | frames: updated_frames}
  end

  defp handle_release_timeout(%__MODULE__{} = state, release, frames, seq) do
    case Enum.find(frames, &(&1.seq == seq)) do
      nil ->
        {:ok, no_op(state)}

      frame ->
        handle_timeout_frame(state, release, frame, seq)
    end
  end

  defp handle_timeout_frame(%__MODULE__{} = state, release, frame, seq) do
    case timeout_frame_action(state, frame) do
      :wait ->
        {:ok,
         %{
           state: state,
           transmit_frames: [],
           schedule_timeout_seqs: [seq],
           cancel_timeout_seqs: [],
           signal: nil
         }}

      :lockout ->
        cancel_timeout_seqs = current_release_frame_seqs(release)

        {:ok,
         %{
           state: %{state | lockout: true, in_flight_release: nil},
           transmit_frames: [],
           schedule_timeout_seqs: [],
           cancel_timeout_seqs: cancel_timeout_seqs,
           signal: nil
         }}

      :retransmit ->
        updated_release = update_release_frame_retry(release, seq)
        retransmit_frame = Enum.find(updated_release.frames, &(&1.seq == seq))

        {:ok,
         %{
           state: %{state | in_flight_release: updated_release},
           transmit_frames: [retransmit_frame],
           schedule_timeout_seqs: [seq],
           cancel_timeout_seqs: [],
           signal: nil
         }}
    end
  end

  defp timeout_frame_action(%__MODULE__{wait: true}, _frame), do: :wait

  defp timeout_frame_action(%__MODULE__{max_retransmit: max_retransmit}, %{retries: retries})
       when retries >= max_retransmit,
       do: :lockout

  defp timeout_frame_action(%__MODULE__{}, _frame), do: :retransmit

  defp apply_valid_report_value(
         %__MODULE__{} = state,
         release,
         [oldest | _] = frames,
         report_value
       ) do
    ack_distance = seq_distance(oldest.seq, report_value)
    {acked, remaining} = Enum.split(frames, ack_distance + 1)
    updated_state = %{state | last_report_value: report_value}
    cancel_timeout_seqs = Enum.map(acked, & &1.seq)

    build_ack_transition(updated_state, release, remaining, cancel_timeout_seqs)
  end

  defp build_ack_transition(updated_state, release, [], cancel_timeout_seqs) do
    %{
      state: %{updated_state | in_flight_release: nil},
      transmit_frames: [],
      schedule_timeout_seqs: [],
      cancel_timeout_seqs: cancel_timeout_seqs,
      signal: {:completion, release.metadata}
    }
  end

  defp build_ack_transition(updated_state, release, remaining, cancel_timeout_seqs) do
    %{
      state: %{updated_state | in_flight_release: %{release | frames: remaining}},
      transmit_frames: [],
      schedule_timeout_seqs: [],
      cancel_timeout_seqs: cancel_timeout_seqs,
      signal: nil
    }
  end

  defp increment_frame_retry(%{seq: seq} = frame, seq) do
    Map.update!(frame, :retries, fn retries -> retries + 1 end)
  end

  defp increment_frame_retry(frame, _seq), do: frame

  defp current_release_frame_seqs(nil), do: []
  defp current_release_frame_seqs(%{frames: frames}), do: Enum.map(frames, & &1.seq)

  defp vcid_mismatch?(%{vcid: nil}, _clcw), do: false
  defp vcid_mismatch?(state, %CLCW{} = clcw), do: clcw.vcid != state.vcid

  defp update_flags(state, %CLCW{} = clcw) do
    wait =
      clcw.wait == 1 or clcw.no_rf_available == 1 or clcw.no_bit_lock == 1 or
        clcw.farm_busy == 1

    %{
      state
      | lockout: clcw.lockout == 1,
        wait: wait,
        retransmit: clcw.retransmit == 1
    }
  end

  defp valid_report_value?(%{in_flight_release: nil, last_report_value: nil}, _report_value),
    do: true

  defp valid_report_value?(
         %{in_flight_release: nil, last_report_value: last_report_value},
         report_value
       ) do
    seq_distance(last_report_value, report_value) <= 127
  end

  defp valid_report_value?(%{in_flight_release: %{frames: []}}, _report_value), do: true

  defp valid_report_value?(%{in_flight_release: %{frames: [oldest | frames]}}, report_value) do
    seq_distance(oldest.seq, report_value) < length([oldest | frames])
  end

  defp seq_distance(base, seq), do: rem(seq - base + 256, 256)
end
