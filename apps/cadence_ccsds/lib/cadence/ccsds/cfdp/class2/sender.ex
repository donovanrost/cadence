defmodule Cadence.CCSDS.CFDP.Class2.Sender do
  @moduledoc """
  Pure Class 2 (acknowledged) sending procedure.

  Initial transmission reuses the Class 1 segmenter. Class 2 adds EOF positive
  acknowledgements, deferred or prompted NAK repair, Keep Alive indications,
  Finished acknowledgement, and caller-owned timer effects.
  """

  alias Cadence.CCSDS.CFDP
  alias Cadence.CCSDS.CFDP.Class1

  alias Cadence.CCSDS.CFDP.{
    FaultPolicy,
    FileData,
    FileEffect,
    Indication,
    PDU,
    Transaction,
    Transition
  }

  alias Cadence.CCSDS.CFDP.Directive.{
    Acknowledgement,
    Finished,
    KeepAlive,
    Metadata,
    NegativeAcknowledgement
  }

  @type phase ::
          :ready
          | :sending_data
          | :awaiting_read
          | :awaiting_retransmission_read
          | :eof
          | :waiting_eof_ack
          | :waiting_finished
          | :completed
          | :faulted

  @type t :: %__MODULE__{
          core: Class1.Sender.t(),
          phase: phase(),
          eof_pdu: PDU.t() | nil,
          pending_reads: [{non_neg_integer(), pos_integer()}],
          pending_read: {non_neg_integer(), pos_integer()} | nil,
          read_resume_phase: phase() | nil,
          positive_ack_expirations: non_neg_integer(),
          positive_ack_limit: pos_integer(),
          suspended?: boolean(),
          transmission_mode: :acknowledged
        }

  @enforce_keys [:core]
  defstruct core: nil,
            phase: :ready,
            eof_pdu: nil,
            pending_reads: [],
            pending_read: nil,
            read_resume_phase: nil,
            positive_ack_expirations: 0,
            positive_ack_limit: 1,
            suspended?: false,
            transmission_mode: :acknowledged

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = Map.new(attrs)
    positive_ack_limit = Map.get(attrs, :positive_ack_limit, 1)

    with true <- is_integer(positive_ack_limit) and positive_ack_limit > 0,
         {:ok, core} <-
           attrs
           |> Map.put(:closure_requested?, false)
           |> Class1.Sender.new() do
      {:ok, %__MODULE__{core: core, positive_ack_limit: positive_ack_limit}}
    else
      false -> {:error, {:invalid_field, :positive_ack_limit, positive_ack_limit}}
      {:error, _reason} = error -> error
    end
  end

  @spec next(t()) :: {:ok, Transition.t(t())} | {:error, term()}
  def next(%__MODULE__{suspended?: true}), do: {:error, :transaction_suspended}

  def next(%__MODULE__{phase: phase} = state) when phase in [:ready, :sending_data, :eof] do
    with {:ok, transition} <- Class1.Sender.next(state.core) do
      pdus = Enum.map(transition.pdus, &acknowledged/1)
      core_phase = transition.state.phase

      if core_phase == :completed do
        [eof_pdu] = pdus

        state = %{
          state
          | core: transition.state,
            phase: :waiting_eof_ack,
            eof_pdu: eof_pdu
        }

        indications = Enum.reject(transition.indications, &(&1.type == :transaction_finished))

        {:ok,
         Transition.new(state,
           pdus: pdus,
           indications: indications,
           timers: [{:start, :positive_ack}]
         )}
      else
        state = %{state | core: transition.state, phase: core_phase}

        {:ok,
         Transition.new(state,
           pdus: pdus,
           indications: transition.indications,
           effects: transition.effects
         )}
      end
    end
  end

  def next(%__MODULE__{phase: phase}), do: {:error, {:no_pdu_available, phase}}

  @spec supply_read(t(), binary()) :: {:ok, Transition.t(t())} | {:error, term()}
  def supply_read(%__MODULE__{phase: :awaiting_read} = state, data) do
    with {:ok, transition} <- Class1.Sender.supply_read(state.core, data) do
      state = %{state | core: transition.state, phase: transition.state.phase}
      pdus = Enum.map(transition.pdus, &acknowledged/1)
      {:ok, Transition.new(state, pdus: pdus, effects: transition.effects)}
    end
  end

  def supply_read(
        %__MODULE__{
          phase: :awaiting_retransmission_read,
          pending_read: {offset, length}
        } = state,
        data
      )
      when is_binary(data) do
    if byte_size(data) == length do
      pdu =
        transaction_pdu(
          state,
          %FileData{offset: offset, data: data},
          :toward_file_receiver
        )

      continue_retransmission_reads(state, pdu)
    else
      {:error, {:unexpected_file_read_length, offset, length, byte_size(data)}}
    end
  end

  def supply_read(%__MODULE__{} = state, data),
    do: {:error, {:unexpected_file_read_result, state.phase, data}}

  @spec ingest(t(), PDU.t()) :: {:ok, Transition.t(t())} | {:error, term()}
  def ingest(%__MODULE__{} = state, %PDU{payload: %NegativeAcknowledgement{} = nak} = pdu)
      when state.phase in [:sending_data, :eof, :waiting_eof_ack, :waiting_finished] do
    with :ok <- validate_incoming(state, pdu, :toward_file_sender),
         {:ok, retransmissions, reads} <- retransmissions(state, nak.segment_requests) do
      begin_retransmission_reads(state, retransmissions, reads)
    end
  end

  def ingest(%__MODULE__{} = state, %PDU{payload: %KeepAlive{} = keep_alive} = pdu)
      when state.phase in [:sending_data, :eof, :waiting_eof_ack, :waiting_finished] do
    with :ok <- validate_incoming(state, pdu, :toward_file_sender) do
      indication =
        Indication.new(:keep_alive_received, state.core.transaction_id, %{
          progress: keep_alive.progress
        })

      {:ok, Transition.new(state, indications: [indication])}
    end
  end

  def ingest(
        %__MODULE__{phase: :waiting_eof_ack} = state,
        %PDU{payload: %Acknowledgement{directive: :end_of_file}} = pdu
      ) do
    with :ok <- validate_incoming(state, pdu, :toward_file_sender) do
      state = %{state | phase: :waiting_finished}
      {:ok, Transition.new(state, timers: [{:cancel, :positive_ack}])}
    end
  end

  def ingest(%__MODULE__{} = state, %PDU{payload: %Finished{} = finished} = pdu)
      when state.phase in [:waiting_eof_ack, :waiting_finished] do
    with :ok <- validate_incoming(state, pdu, :toward_file_sender) do
      waiting_for_eof_ack? = state.phase == :waiting_eof_ack

      acknowledgement = %Acknowledgement{
        directive: :finished,
        condition: finished.condition,
        transaction_status: :terminated
      }

      terminal_phase = if(finished.condition == :no_error, do: :completed, else: :faulted)
      state = %{state | phase: terminal_phase}
      type = if(terminal_phase == :completed, do: :transaction_finished, else: :transaction_fault)

      indication =
        Indication.new(type, state.core.transaction_id, %{
          condition: finished.condition,
          delivery_code: finished.delivery_code,
          file_status: finished.file_status
        })

      timers = if(waiting_for_eof_ack?, do: [{:cancel, :positive_ack}], else: [])

      {:ok,
       Transition.new(state,
         pdus: [transaction_pdu(state, acknowledgement, :toward_file_receiver)],
         indications: [indication],
         timers: timers
       )}
    end
  end

  def ingest(%__MODULE__{} = state, %PDU{} = pdu),
    do: {:error, {:unexpected_pdu, state.phase, pdu.payload}}

  @spec timer_expired(t(), Transition.timer()) :: {:ok, Transition.t(t())} | {:error, term()}
  def timer_expired(%__MODULE__{suspended?: true}, timer),
    do: {:error, {:transaction_suspended, timer}}

  def timer_expired(%__MODULE__{phase: :waiting_eof_ack} = state, :positive_ack) do
    expirations = state.positive_ack_expirations + 1

    if expirations >= state.positive_ack_limit do
      fault(%{state | positive_ack_expirations: expirations}, :positive_ack_limit_reached)
    else
      state = %{state | positive_ack_expirations: expirations}

      {:ok,
       Transition.new(state,
         pdus: [state.eof_pdu],
         timers: [{:start, :positive_ack}]
       )}
    end
  end

  def timer_expired(%__MODULE__{} = state, timer),
    do: {:error, {:unexpected_timer_expiration, state.phase, timer}}

  @spec suspend(t(), CFDP.condition()) :: {:ok, Transition.t(t())} | {:error, term()}
  def suspend(state, condition \\ :suspend_request_received)

  def suspend(%__MODULE__{phase: phase}, _condition)
      when phase in [:completed, :faulted],
      do: {:error, {:transaction_terminal, phase}}

  def suspend(%__MODULE__{suspended?: true} = state, _condition),
    do: {:ok, Transition.new(state)}

  def suspend(%__MODULE__{} = state, condition) do
    state = %{state | suspended?: true}
    indication = Indication.new(:suspended, state.core.transaction_id, %{condition: condition})

    timers =
      if state.phase in [:waiting_eof_ack], do: [{:cancel, :positive_ack}], else: []

    {:ok, Transition.new(state, indications: [indication], timers: timers)}
  end

  @spec resume(t()) :: {:ok, Transition.t(t())} | {:error, term()}
  def resume(%__MODULE__{suspended?: false}), do: {:error, :transaction_not_suspended}

  def resume(%__MODULE__{} = state) do
    state = %{state | suspended?: false}

    indication =
      Indication.new(:resumed, state.core.transaction_id, %{progress: state.core.next_offset})

    timers =
      if state.phase in [:waiting_eof_ack], do: [{:start, :positive_ack}], else: []

    {:ok, Transition.new(state, indications: [indication], timers: timers)}
  end

  defp retransmissions(state, requests) when is_list(requests) do
    Enum.reduce_while(requests, {:ok, [], []}, fn request, {:ok, pdus, reads} ->
      case retransmit_request(state, request) do
        {:ok, values, requested_reads} ->
          {:cont, {:ok, [values | pdus], [requested_reads | reads]}}

        {:error, _reason} = error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, pdus, reads} ->
        {:ok, pdus |> Enum.reverse() |> List.flatten(), reads |> Enum.reverse() |> List.flatten()}

      {:error, _reason} = error ->
        error
    end
  end

  defp retransmissions(_state, value), do: {:error, {:invalid_segment_requests, value}}

  defp retransmit_request(state, {0, 0}) do
    metadata = %Metadata{
      closure_requested?: false,
      checksum_type: state.core.checksum_type,
      file_size: state.core.file_size,
      source_file_name: state.core.source_file_name,
      destination_file_name: state.core.destination_file_name,
      options: state.core.options
    }

    {:ok, [transaction_pdu(state, metadata, :toward_file_receiver)], []}
  end

  defp retransmit_request(state, {start_offset, end_offset})
       when is_integer(start_offset) and is_integer(end_offset) and start_offset >= 0 and
              end_offset > start_offset and end_offset <= state.core.file_size do
    reads =
      start_offset
      |> offsets(end_offset, state.core.segment_octets)
      |> Enum.map(&{&1, min(state.core.segment_octets, end_offset - &1)})

    if is_binary(state.core.file) do
      pdus =
        Enum.map(reads, fn {offset, length} ->
          data = binary_part(state.core.file, offset, length)
          transaction_pdu(state, %FileData{offset: offset, data: data}, :toward_file_receiver)
        end)

      {:ok, pdus, []}
    else
      {:ok, [], reads}
    end
  end

  defp retransmit_request(_state, request), do: {:error, {:invalid_segment_request, request}}

  defp offsets(start_offset, end_offset, segment_octets) do
    Stream.unfold(start_offset, fn
      offset when offset < end_offset -> {offset, offset + segment_octets}
      _offset -> nil
    end)
  end

  defp begin_retransmission_reads(state, pdus, []),
    do: {:ok, Transition.new(state, pdus: pdus)}

  defp begin_retransmission_reads(state, pdus, [read | pending_reads]) do
    state = %{
      state
      | phase: :awaiting_retransmission_read,
        pending_read: read,
        pending_reads: pending_reads,
        read_resume_phase: state.phase
    }

    {:ok, Transition.new(state, pdus: pdus, effects: [read_effect(state, read)])}
  end

  defp continue_retransmission_reads(%__MODULE__{pending_reads: []} = state, pdu) do
    state = %{
      state
      | phase: state.read_resume_phase,
        pending_read: nil,
        read_resume_phase: nil
    }

    {:ok, Transition.new(state, pdus: [pdu])}
  end

  defp continue_retransmission_reads(%__MODULE__{pending_reads: [read | rest]} = state, pdu) do
    state = %{state | pending_read: read, pending_reads: rest}
    {:ok, Transition.new(state, pdus: [pdu], effects: [read_effect(state, read)])}
  end

  defp read_effect(state, {offset, length}) do
    FileEffect.new(:read, state.core.source, state.core.transaction_id,
      offset: offset,
      length: length,
      details: %{retransmission?: true}
    )
  end

  defp acknowledged(%PDU{} = pdu), do: %{pdu | transmission_mode: :acknowledged}

  defp validate_incoming(state, pdu, direction),
    do: Transaction.validate_incoming(pdu, transaction_state(state), direction)

  defp transaction_pdu(state, payload, direction),
    do: Transaction.pdu(transaction_state(state), payload, direction)

  defp transaction_state(state) do
    %{
      transaction_id: state.core.transaction_id,
      destination_entity_id: state.core.destination_entity_id,
      transmission_mode: :acknowledged,
      crc?: state.core.crc?,
      large_file?: state.core.large_file?,
      entity_id_octets: state.core.entity_id_octets,
      sequence_number_octets: state.core.sequence_number_octets
    }
  end

  defp fault(state, condition) do
    case FaultPolicy.handler(state.core.fault_policy, condition, state.core.options) do
      :cancel ->
        terminal_fault(state, :transaction_fault, condition)

      :abandon ->
        terminal_fault(state, :abandoned, condition)

      :suspend ->
        suspend(state, condition)

      :ignore ->
        indication =
          Indication.new(:fault, state.core.transaction_id, %{
            condition: condition,
            progress: state.core.next_offset
          })

        {:ok,
         Transition.new(state,
           indications: [indication],
           timers: [{:start, :positive_ack}]
         )}
    end
  end

  defp terminal_fault(state, type, condition) do
    state = %{state | phase: :faulted}

    indication =
      Indication.new(type, state.core.transaction_id, %{
        condition: condition,
        progress: state.core.next_offset
      })

    {:ok, Transition.new(state, indications: [indication])}
  end
end
