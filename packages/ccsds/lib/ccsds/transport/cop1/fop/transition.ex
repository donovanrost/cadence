defmodule CCSDS.Transport.COP1.FOP.Transition do
  @moduledoc """
  Observable effects produced by one FOP-1 state-table event.

  The state machine remains pure: callers execute transmit, abort, timer, and
  notification effects, then feed lower-layer responses and CLCWs back into
  FOP-1.
  """

  @type timer_action :: :none | :start | :cancel
  @type frame_type :: :ad | :bd | :bc

  @type transmit_request :: %{
          frame_type: frame_type(),
          frame: map() | nil,
          control_command: term() | nil
        }

  @type notification ::
          {:fdu, :accept | :reject | :positive_confirm | :negative_confirm, term()}
          | {:directive, :accept | :reject | :positive_confirm | :negative_confirm, term()}
          | {:suspend, non_neg_integer()}

  @type t :: %{
          state: struct(),
          event: atom() | nil,
          transmit_requests: [transmit_request()],
          abort_lower?: boolean(),
          timer_action: timer_action(),
          notifications: [notification()],
          alerts: [atom()],
          signals: [term()],
          signal: term() | nil,
          transmit_frames: [map()],
          transmit_bc_commands: [term()],
          schedule_timeout_seqs: [non_neg_integer()],
          cancel_timeout_seqs: [non_neg_integer()]
        }

  @spec new(struct(), atom() | nil) :: t()
  def new(state, event \\ nil) when is_struct(state) do
    %{
      state: state,
      event: event,
      transmit_requests: [],
      abort_lower?: false,
      timer_action: :none,
      notifications: [],
      alerts: [],
      signals: [],
      signal: nil,
      transmit_frames: [],
      transmit_bc_commands: [],
      schedule_timeout_seqs: [],
      cancel_timeout_seqs: []
    }
  end

  @spec put_state(t(), struct()) :: t()
  def put_state(transition, state), do: %{transition | state: state}

  @spec put_event(t(), atom()) :: t()
  def put_event(transition, event), do: %{transition | event: event}

  @spec put_timer(t(), timer_action()) :: t()
  def put_timer(transition, timer_action), do: %{transition | timer_action: timer_action}

  @spec abort_lower(t()) :: t()
  def abort_lower(transition), do: %{transition | abort_lower?: true}

  @spec add_transmit(t(), frame_type(), map() | nil, term() | nil) :: t()
  def add_transmit(transition, frame_type, frame \\ nil, control_command \\ nil) do
    request = %{
      frame_type: frame_type,
      frame: frame,
      control_command: control_command
    }

    transition = %{
      transition
      | transmit_requests: transition.transmit_requests ++ [request]
    }

    case frame_type do
      type when type in [:ad, :bd] ->
        %{
          transition
          | transmit_frames: transition.transmit_frames ++ [frame],
            schedule_timeout_seqs:
              maybe_append_sequence(transition.schedule_timeout_seqs, type, frame)
        }

      :bc ->
        %{
          transition
          | transmit_bc_commands: transition.transmit_bc_commands ++ [control_command]
        }
    end
  end

  @spec add_notification(t(), notification()) :: t()
  def add_notification(transition, notification) do
    %{transition | notifications: transition.notifications ++ [notification]}
  end

  @spec add_alert(t(), atom()) :: t()
  def add_alert(transition, reason), do: %{transition | alerts: transition.alerts ++ [reason]}

  @spec add_signal(t(), term()) :: t()
  def add_signal(transition, signal) do
    signals = transition.signals ++ [signal]
    %{transition | signals: signals, signal: List.first(signals)}
  end

  @spec cancel_sequences(t(), [non_neg_integer()]) :: t()
  def cancel_sequences(transition, sequences) do
    %{
      transition
      | cancel_timeout_seqs: Enum.uniq(transition.cancel_timeout_seqs ++ sequences)
    }
  end

  defp maybe_append_sequence(sequences, :ad, %{seq: sequence_number})
       when is_integer(sequence_number),
       do: Enum.uniq(sequences ++ [sequence_number])

  defp maybe_append_sequence(sequences, _frame_type, _frame), do: sequences
end
