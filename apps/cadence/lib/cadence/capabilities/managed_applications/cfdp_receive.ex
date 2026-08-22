defmodule Cadence.Capabilities.ManagedApplications.CFDPReceive do
  @moduledoc """
  Bounded Class-1 CFDP receive runtime proof.

  This adapter deliberately supports only unacknowledged receive transactions,
  in-memory files, and closure-disabled metadata. Outbound transport and durable
  filestore effects remain outside this capability until their product contracts
  are defined.
  """

  @behaviour Cadence.ApplicationDispatch.Handler
  @behaviour Cadence.Capabilities.Family
  @behaviour Cadence.Capabilities.ManagedApplication

  alias Cadence.ActionRequests.{CancelTimer, ScheduleTimer}
  alias Cadence.ApplicationDispatch.WorkItem
  alias Cadence.Capabilities.Definitions.CFDPReceive, as: Definition
  alias Cadence.Capabilities.ExecutionContext
  alias Cadence.Capabilities.ExecutionResult
  alias Cadence.CFDP.TransactionEvent
  alias Cadence.Protocol.PacketRecord
  alias CCSDS.CFDP.Class1.Receiver
  alias CCSDS.CFDP.Codec
  alias CCSDS.CFDP.Directive.EndOfFile
  alias CCSDS.CFDP.Directive.Metadata
  alias CCSDS.CFDP.FileData
  alias CCSDS.CFDP.PDU
  alias CCSDS.CFDP.Transition

  @impl true
  defdelegate descriptor(), to: Definition

  @impl true
  def handler_key, do: :cfdp_receive

  @impl true
  defdelegate validate_config(configuration, validation_context), to: Definition

  @impl true
  def build_instance(configuration, _activation_context) do
    Definition.normalize_config(configuration)
  end

  @impl true
  def init_instance(configuration, %ExecutionContext{}) do
    with {:ok, normalized} <- Definition.normalize_config(configuration) do
      {:ok,
       ExecutionResult.new(%{
         state: %{
           configuration: normalized,
           transactions: %{},
           pdu_count: 0,
           completed_count: 0,
           faulted_count: 0,
           last_event_types: []
         }
       })}
    end
  end

  @impl true
  def handle_record(%PacketRecord{} = record, state, %ExecutionContext{})
      when is_map(state) do
    with {:ok, %PDU{} = pdu} <- Codec.decode(record.packet_data),
         :ok <- supported_pdu(pdu, state.configuration.max_in_memory_file_octets),
         {:ok, receiver} <- fetch_or_start_receiver(state, pdu),
         {:ok, %Transition{} = transition} <- Receiver.ingest(receiver, pdu),
         :ok <- supported_transition(transition) do
      result(state, pdu, transition, true)
    end
  end

  def handle_record(%PacketRecord{}, state, %ExecutionContext{}),
    do: {:error, {:invalid_cfdp_receive_state, state}}

  def handle_record(record, _state, %ExecutionContext{}),
    do: {:error, {:unsupported_cfdp_receive_record, record}}

  @impl true
  def handle_timer(timer_key, state, %ExecutionContext{}) when is_map(state) do
    with {:ok, transaction_key, receiver} <- receiver_for_timer(state, timer_key),
         {:ok, %Transition{} = transition} <- Receiver.timer_expired(receiver, :check),
         :ok <- supported_transition(transition) do
      result(state, transaction_key, transition, false)
    end
  end

  def handle_timer(_timer_key, state, %ExecutionContext{}),
    do: {:error, {:invalid_cfdp_receive_state, state}}

  @impl true
  def snapshot_state(state, %ExecutionContext{}) when is_map(state) do
    transactions =
      state.transactions
      |> Enum.map(fn {transaction_key, receiver} ->
        %{
          transaction_key: transaction_key,
          phase: receiver.phase,
          progress_octets: Receiver.progress(receiver),
          expected_file_octets: expected_file_octets(receiver)
        }
      end)
      |> Enum.sort_by(& &1.transaction_key)

    {:ok,
     %{
       local_entity_id: state.configuration.local_entity_id,
       active_transaction_count: length(transactions),
       pdu_count: state.pdu_count,
       completed_count: state.completed_count,
       faulted_count: state.faulted_count,
       last_event_types: state.last_event_types,
       transactions: transactions
     }}
  end

  def snapshot_state(state, %ExecutionContext{}),
    do: {:error, {:invalid_cfdp_receive_state, state}}

  @impl true
  def handle(_packet_record, %WorkItem{}), do: {:error, :runtime_execution_required}

  defp supported_pdu(
         %PDU{
           direction: :toward_file_receiver,
           transmission_mode: :unacknowledged,
           payload: %Metadata{closure_requested?: false, file_size: file_size}
         },
         maximum
       )
       when file_size <= maximum,
       do: :ok

  defp supported_pdu(
         %PDU{
           direction: :toward_file_receiver,
           transmission_mode: :unacknowledged,
           payload: %FileData{offset: offset, data: data}
         },
         maximum
       )
       when offset + byte_size(data) <= maximum,
       do: :ok

  defp supported_pdu(
         %PDU{
           direction: :toward_file_receiver,
           transmission_mode: :unacknowledged,
           payload: %EndOfFile{file_size: file_size}
         },
         maximum
       )
       when file_size <= maximum,
       do: :ok

  defp supported_pdu(%PDU{payload: %Metadata{closure_requested?: true}}, _maximum),
    do: {:error, :cfdp_closure_transport_not_configured}

  defp supported_pdu(%PDU{} = pdu, _maximum),
    do: {:error, {:unsupported_cfdp_receive_pdu, pdu}}

  defp fetch_or_start_receiver(state, %PDU{} = pdu) do
    transaction_key = transaction_key(pdu)

    case Map.fetch(state.transactions, transaction_key) do
      {:ok, receiver} ->
        {:ok, receiver}

      :error ->
        if map_size(state.transactions) < state.configuration.max_active_transactions do
          Receiver.new(state.configuration.local_entity_id,
            check_limit: state.configuration.check_limit
          )
        else
          {:error, :cfdp_active_transaction_limit_reached}
        end
    end
  end

  defp supported_transition(%Transition{pdus: [], effects: []}), do: :ok

  defp supported_transition(%Transition{pdus: [_ | _]}),
    do: {:error, :cfdp_outbound_transport_not_configured}

  defp supported_transition(%Transition{effects: [_ | _]}),
    do: {:error, :cfdp_filestore_not_configured}

  defp result(state, %PDU{} = pdu, transition, increment_pdu_count?) do
    result(state, transaction_key(pdu), transition, increment_pdu_count?)
  end

  defp result(state, transaction_key, %Transition{} = transition, increment_pdu_count?) do
    events = Enum.map(transition.indications, &TransactionEvent.from_indication/1)
    next_state = update_state(state, transaction_key, transition, events, increment_pdu_count?)

    {:ok,
     ExecutionResult.new(%{
       state: next_state,
       records: events,
       action_requests: timer_requests(transaction_key, transition.timers, state.configuration)
     })}
  end

  defp update_state(state, transaction_key, transition, events, increment_pdu_count?) do
    terminal? = transition.state.phase in [:completed, :faulted]

    transactions =
      if terminal? do
        Map.delete(state.transactions, transaction_key)
      else
        Map.put(state.transactions, transaction_key, transition.state)
      end

    event_types = Enum.map(events, & &1.event_type)

    %{
      state
      | transactions: transactions,
        pdu_count: state.pdu_count + if(increment_pdu_count?, do: 1, else: 0),
        completed_count:
          state.completed_count + if(transition.state.phase == :completed, do: 1, else: 0),
        faulted_count:
          state.faulted_count + if(transition.state.phase == :faulted, do: 1, else: 0),
        last_event_types: Enum.take(state.last_event_types ++ event_types, -20)
    }
  end

  defp timer_requests(transaction_key, timer_effects, configuration) do
    Enum.map(timer_effects, fn
      {:start, :check} ->
        ScheduleTimer.new(%{
          timer_key: timer_key(transaction_key),
          delay_ms: configuration.check_interval_ms,
          metadata: %{protocol: :cfdp, transaction_key: transaction_key, timer: :check}
        })

      {:cancel, :check} ->
        CancelTimer.new(%{timer_key: timer_key(transaction_key)})
    end)
  end

  defp receiver_for_timer(state, timer_key) do
    case Enum.find(state.transactions, fn {transaction_key, _receiver} ->
           timer_key(transaction_key) == timer_key
         end) do
      {transaction_key, receiver} -> {:ok, transaction_key, receiver}
      nil -> {:error, {:unknown_cfdp_receive_timer, timer_key}}
    end
  end

  defp transaction_key(%PDU{} = pdu),
    do: "#{pdu.source_entity_id}:#{pdu.transaction_sequence_number}"

  defp timer_key(transaction_key), do: "cfdp:#{transaction_key}:check"

  defp expected_file_octets(%Receiver{metadata: %Metadata{file_size: file_size}}),
    do: file_size

  defp expected_file_octets(%Receiver{}), do: nil
end
