defmodule Cadence.CCSDS.Transport.COP1.FARM do
  @moduledoc """
  Pure COP-1 Frame Acceptance and Reporting Mechanism (FARM-1).

  One state value represents one TC Virtual Channel. `process_frame/3`
  implements FARM-1 events E1 through E9, `buffer_released/1` implements E10,
  and `clcw/1` reports the E11 state.
  """

  alias Cadence.CCSDS.Core.LinkFrame
  alias Cadence.CCSDS.Transport.COP1.{CLCW, ControlCommand}

  @type state_name :: :open | :wait | :lockout
  @type disposition :: :accept | :discard | :ignore | :report
  @type event :: :e1 | :e2 | :e3 | :e4 | :e5 | :e6 | :e7 | :e8 | :e9 | :e10 | :e11
  @type frame_type :: :ad | :bd | :bc | nil

  @type transition :: %{
          state: t(),
          event: event(),
          disposition: disposition(),
          frame_type: frame_type(),
          deliver?: boolean(),
          control_command: ControlCommand.t() | nil,
          control_command_executed?: boolean()
        }

  @type t :: %__MODULE__{
          vcid: 0..63,
          state: state_name(),
          retransmit: boolean(),
          receiver_frame_sequence_number: 0..255,
          farm_b_counter: non_neg_integer(),
          sliding_window_width: 1..256,
          positive_window_width: 1..256,
          negative_window_width: 0..127,
          retransmission_allowed: boolean()
        }

  defstruct vcid: 0,
            state: :open,
            retransmit: false,
            receiver_frame_sequence_number: 0,
            farm_b_counter: 0,
            sliding_window_width: 254,
            positive_window_width: 127,
            negative_window_width: 127,
            retransmission_allowed: true

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs \\ %{}) when is_map(attrs) or is_list(attrs) do
    attrs = Map.new(attrs)
    positive_window_width = Map.get(attrs, :positive_window_width, 127)
    negative_window_width = Map.get(attrs, :negative_window_width, 127)

    computed_sliding_window_width =
      if is_integer(positive_window_width) and is_integer(negative_window_width) do
        positive_window_width + negative_window_width
      end

    farm =
      struct(
        __MODULE__,
        Map.put_new(attrs, :sliding_window_width, computed_sliding_window_width)
      )

    with :ok <- validate_range(farm.vcid, 0, 63, :vcid),
         :ok <- validate_state(farm.state),
         :ok <- validate_boolean(farm.retransmit, :retransmit),
         :ok <-
           validate_range(
             farm.receiver_frame_sequence_number,
             0,
             255,
             :receiver_frame_sequence_number
           ),
         :ok <- validate_non_negative(farm.farm_b_counter, :farm_b_counter),
         :ok <- validate_boolean(farm.retransmission_allowed, :retransmission_allowed),
         :ok <- validate_sliding_window_sum(farm),
         :ok <- validate_window(farm) do
      {:ok, farm}
    end
  rescue
    KeyError -> {:error, :unknown_farm_attribute}
  end

  @spec process_frame(t(), LinkFrame.t(), keyword()) ::
          {:ok, transition()} | {:error, term()}
  def process_frame(%__MODULE__{} = farm, %LinkFrame{} = frame, opts \\ []) do
    buffer_available? = Keyword.get(opts, :buffer_available?, true)

    with :ok <- validate_frame(farm, frame),
         :ok <- validate_boolean(buffer_available?, :buffer_available?) do
      if frame.quality == :good do
        process_valid_frame(farm, frame, buffer_available?)
      else
        {:ok, invalid_frame(farm)}
      end
    end
  end

  @spec invalid_frame(t()) :: transition()
  def invalid_frame(%__MODULE__{} = farm) do
    transition(farm, :e9, :discard, nil)
  end

  @spec buffer_released(t()) :: transition()
  def buffer_released(%__MODULE__{state: :wait} = farm) do
    transition(%{farm | state: :open}, :e10, :ignore, nil)
  end

  def buffer_released(%__MODULE__{} = farm) do
    transition(farm, :e10, :ignore, nil)
  end

  @spec clcw(t()) :: CLCW.t()
  def clcw(%__MODULE__{} = farm) do
    CLCW.new(%{
      vcid: farm.vcid,
      lockout: flag(farm.state == :lockout),
      wait: flag(farm.state == :wait),
      retransmit: flag(farm.retransmit),
      farm_b_counter: rem(farm.farm_b_counter, 4),
      report_value: farm.receiver_frame_sequence_number
    })
  end

  defp process_valid_frame(farm, frame, buffer_available?) do
    case {Map.get(frame.meta, :bypass_flag), Map.get(frame.meta, :control_command_flag)} do
      {0, 0} -> {:ok, process_ad_frame(farm, frame.frame_seq, buffer_available?)}
      {1, 0} -> {:ok, process_bd_frame(farm)}
      {1, 1} -> process_bc_frame(farm, frame.payload_octets)
      {0, 1} -> {:error, :reserved_frame_type}
      flags -> {:error, {:invalid_frame_type_flags, flags}}
    end
  end

  defp process_ad_frame(%__MODULE__{state: :lockout} = farm, sequence_number, buffer_available?) do
    event = classify_ad_event(farm, sequence_number, buffer_available?)
    transition(farm, event, :discard, :ad)
  end

  defp process_ad_frame(%__MODULE__{state: :wait} = farm, sequence_number, _buffer_available?) do
    event = classify_ad_event(farm, sequence_number, false)

    if event == :e5 do
      transition(%{farm | state: :lockout}, event, :discard, :ad)
    else
      transition(farm, event, :discard, :ad)
    end
  end

  defp process_ad_frame(%__MODULE__{state: :open} = farm, sequence_number, buffer_available?) do
    case classify_ad_event(farm, sequence_number, buffer_available?) do
      :e1 ->
        next_farm = %{
          farm
          | receiver_frame_sequence_number: increment_sequence_number(sequence_number),
            retransmit: false
        }

        transition(next_farm, :e1, :accept, :ad, deliver?: true)

      :e2 ->
        transition(%{farm | state: :wait, retransmit: true}, :e2, :discard, :ad)

      :e3 ->
        transition(%{farm | retransmit: true}, :e3, :discard, :ad)

      :e4 ->
        transition(farm, :e4, :discard, :ad)

      :e5 ->
        transition(%{farm | state: :lockout}, :e5, :discard, :ad)
    end
  end

  defp process_bd_frame(farm) do
    farm
    |> increment_farm_b_counter()
    |> transition(:e6, :accept, :bd, deliver?: true)
  end

  defp process_bc_frame(farm, command_octets) do
    case ControlCommand.decode(command_octets) do
      {:ok, :unlock} ->
        {:ok, process_unlock(farm)}

      {:ok, {:set_vr, receiver_frame_sequence_number} = command} ->
        {:ok, process_set_vr(farm, receiver_frame_sequence_number, command)}

      {:error, _reason} ->
        {:ok, invalid_frame(farm)}
    end
  end

  defp process_unlock(farm) do
    next_farm =
      farm
      |> increment_farm_b_counter()
      |> Map.put(:state, :open)
      |> Map.put(:retransmit, false)

    transition(next_farm, :e7, :accept, :bc,
      control_command: :unlock,
      control_command_executed?: true
    )
  end

  defp process_set_vr(
         %__MODULE__{state: :lockout} = farm,
         _receiver_frame_sequence_number,
         command
       ) do
    farm
    |> increment_farm_b_counter()
    |> transition(:e8, :accept, :bc,
      control_command: command,
      control_command_executed?: false
    )
  end

  defp process_set_vr(farm, receiver_frame_sequence_number, command) do
    next_farm = %{
      increment_farm_b_counter(farm)
      | state: :open,
        retransmit: false,
        receiver_frame_sequence_number: receiver_frame_sequence_number
    }

    transition(next_farm, :e8, :accept, :bc,
      control_command: command,
      control_command_executed?: true
    )
  end

  defp classify_ad_event(farm, sequence_number, buffer_available?) do
    forward_distance = modulo(sequence_number - farm.receiver_frame_sequence_number, 256)
    backward_distance = modulo(farm.receiver_frame_sequence_number - sequence_number, 256)

    cond do
      forward_distance == 0 and buffer_available? -> :e1
      forward_distance == 0 -> :e2
      forward_distance <= farm.positive_window_width - 1 -> :e3
      backward_distance <= farm.negative_window_width -> :e4
      true -> :e5
    end
  end

  defp increment_farm_b_counter(farm), do: %{farm | farm_b_counter: farm.farm_b_counter + 1}
  defp increment_sequence_number(sequence_number), do: rem(sequence_number + 1, 256)
  defp modulo(value, modulus), do: Integer.mod(value, modulus)
  defp flag(true), do: 1
  defp flag(false), do: 0

  defp transition(farm, event, disposition, frame_type, opts \\ []) do
    %{
      state: farm,
      event: event,
      disposition: disposition,
      frame_type: frame_type,
      deliver?: Keyword.get(opts, :deliver?, false),
      control_command: Keyword.get(opts, :control_command),
      control_command_executed?: Keyword.get(opts, :control_command_executed?, false)
    }
  end

  defp validate_frame(farm, %LinkFrame{profile: :tc, vcid: vcid, frame_seq: sequence_number}) do
    case validate_matching_vcid(vcid, farm.vcid) do
      :ok -> validate_range(sequence_number, 0, 255, :frame_seq)
      {:error, _reason} = error -> error
    end
  end

  defp validate_frame(_farm, %LinkFrame{profile: profile}),
    do: {:error, {:invalid_profile, profile}}

  defp validate_matching_vcid(vcid, vcid), do: :ok

  defp validate_matching_vcid(frame_vcid, farm_vcid),
    do: {:error, {:vcid_mismatch, farm_vcid, frame_vcid}}

  defp validate_window(%__MODULE__{retransmission_allowed: true} = farm) do
    with :ok <- validate_range(farm.positive_window_width, 1, 127, :positive_window_width),
         :ok <- validate_range(farm.negative_window_width, 1, 127, :negative_window_width),
         :ok <- validate_equal_windows(farm),
         :ok <- validate_range(farm.sliding_window_width, 2, 254, :sliding_window_width) do
      if rem(farm.sliding_window_width, 2) == 0 do
        :ok
      else
        {:error, {:invalid_field, :sliding_window_width, farm.sliding_window_width}}
      end
    end
  end

  defp validate_window(%__MODULE__{retransmission_allowed: false} = farm) do
    with :ok <- validate_range(farm.positive_window_width, 1, 256, :positive_window_width),
         :ok <- validate_range(farm.negative_window_width, 0, 127, :negative_window_width) do
      validate_range(farm.sliding_window_width, 1, 256, :sliding_window_width)
    end
  end

  defp validate_sliding_window_sum(farm)
       when is_integer(farm.positive_window_width) and
              is_integer(farm.negative_window_width) and
              farm.sliding_window_width ==
                farm.positive_window_width + farm.negative_window_width,
       do: :ok

  defp validate_sliding_window_sum(farm) do
    {:error,
     {:invalid_sliding_window_width, farm.sliding_window_width, farm.positive_window_width,
      farm.negative_window_width}}
  end

  defp validate_equal_windows(%__MODULE__{
         positive_window_width: width,
         negative_window_width: width
       }),
       do: :ok

  defp validate_equal_windows(farm),
    do:
      {:error,
       {:unequal_retransmission_windows, farm.positive_window_width, farm.negative_window_width}}

  defp validate_state(state) when state in [:open, :wait, :lockout], do: :ok
  defp validate_state(state), do: {:error, {:invalid_field, :state, state}}

  defp validate_boolean(value, _field) when is_boolean(value), do: :ok
  defp validate_boolean(value, field), do: {:error, {:invalid_field, field, value}}

  defp validate_non_negative(value, _field) when is_integer(value) and value >= 0, do: :ok
  defp validate_non_negative(value, field), do: {:error, {:invalid_field, field, value}}

  defp validate_range(value, min, max, _field)
       when is_integer(value) and value >= min and value <= max,
       do: :ok

  defp validate_range(value, _min, _max, field),
    do: {:error, {:invalid_field, field, value}}
end
