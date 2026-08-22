defmodule CCSDS.CFDP.Class2.Receiver do
  @moduledoc """
  Pure Class 2 (acknowledged) receiving procedure.

  Deferred, immediate, and caller-triggered asynchronous NAK paths are
  supported. Prompt responses, NAK limits, Finished positive acknowledgements,
  and retransmission timer effects are explicit.
  """

  alias CCSDS.CFDP
  alias CCSDS.CFDP.Class1
  alias CCSDS.CFDP.{FaultPolicy, FileData, Indication, PDU, Transaction, Transition}

  alias CCSDS.CFDP.Directive.{
    Acknowledgement,
    EndOfFile,
    Finished,
    KeepAlive,
    NegativeAcknowledgement,
    Prompt
  }

  alias CCSDS.CFDP.TLV.EntityID

  @type phase ::
          :receiving
          | :waiting_repair
          | :verifying
          | :finalizing
          | :waiting_finished_ack
          | :completed
          | :faulted

  @type t :: %__MODULE__{
          core: Class1.Receiver.t(),
          phase: phase(),
          last_finished_pdu: PDU.t() | nil,
          pending_indication: Indication.t() | nil,
          nak_expirations: non_neg_integer(),
          nak_limit: pos_integer(),
          positive_ack_expirations: non_neg_integer(),
          positive_ack_limit: pos_integer(),
          immediate_nak?: boolean(),
          suspended?: boolean(),
          transmission_mode: :acknowledged
        }

  @enforce_keys [:core]
  defstruct core: nil,
            phase: :receiving,
            last_finished_pdu: nil,
            pending_indication: nil,
            nak_expirations: 0,
            nak_limit: 1,
            positive_ack_expirations: 0,
            positive_ack_limit: 1,
            immediate_nak?: false,
            suspended?: false,
            transmission_mode: :acknowledged

  @spec new(non_neg_integer(), keyword()) :: {:ok, t()} | {:error, term()}
  def new(local_entity_id, opts \\ []) when is_list(opts) do
    nak_limit = Keyword.get(opts, :nak_limit, 1)
    positive_ack_limit = Keyword.get(opts, :positive_ack_limit, 1)
    immediate_nak? = Keyword.get(opts, :immediate_nak?, false)

    with :ok <- validate_limit(nak_limit, :nak_limit),
         :ok <- validate_limit(positive_ack_limit, :positive_ack_limit),
         :ok <- validate_boolean(immediate_nak?, :immediate_nak?),
         {:ok, core} <-
           Class1.Receiver.new(
             local_entity_id,
             Keyword.put(opts, :suspension_allowed?, true)
           ) do
      {:ok,
       %__MODULE__{
         core: core,
         nak_limit: nak_limit,
         positive_ack_limit: positive_ack_limit,
         immediate_nak?: immediate_nak?
       }}
    end
  end

  @spec ingest(t(), PDU.t()) :: {:ok, Transition.t(t())} | {:error, term()}
  def ingest(%__MODULE__{phase: phase}, %PDU{}) when phase in [:completed, :faulted],
    do: {:error, {:transaction_terminal, phase}}

  def ingest(
        %__MODULE__{phase: :waiting_finished_ack} = state,
        %PDU{payload: %Acknowledgement{directive: :finished}} = pdu
      ) do
    with :ok <- validate_incoming(state, pdu, :toward_file_receiver) do
      terminal_phase =
        if state.pending_indication.type == :transaction_finished, do: :completed, else: :faulted

      state = %{state | phase: terminal_phase}

      {:ok,
       Transition.new(state,
         indications: [state.pending_indication],
         timers: [{:cancel, :positive_ack}]
       )}
    end
  end

  def ingest(%__MODULE__{} = state, %PDU{payload: %Prompt{} = prompt} = pdu)
      when state.phase in [:receiving, :waiting_repair] do
    with :ok <- validate_incoming(state, pdu, :toward_file_receiver) do
      prompt_transition(state, prompt)
    end
  end

  def ingest(%__MODULE__{} = state, %PDU{} = pdu)
      when state.phase in [:receiving, :waiting_repair] do
    gap_detected? = gap_detected?(state, pdu.payload)

    with :ok <- validate_initial_or_bound(state, pdu),
         {:ok, core_transition} <- Class1.Receiver.ingest(state.core, unacknowledged(pdu)) do
      apply_core_transition(state, pdu.payload, core_transition, gap_detected?)
    end
  end

  def ingest(%__MODULE__{} = state, %PDU{} = pdu),
    do: {:error, {:unexpected_pdu, state.phase, pdu.payload}}

  @spec checksum_result(t(), {:ok, 0..0xFFFFFFFF} | {:error, term()}) ::
          {:ok, Transition.t(t())} | {:error, term()}
  def checksum_result(%__MODULE__{phase: :verifying} = state, result) do
    with {:ok, transition} <- Class1.Receiver.checksum_result(state.core, result) do
      apply_core_transition(state, nil, transition)
    end
  end

  def checksum_result(%__MODULE__{} = state, result),
    do: {:error, {:unexpected_checksum_result, state.phase, result}}

  @spec finalize_result(t(), :ok | {:error, term()}) ::
          {:ok, Transition.t(t())} | {:error, term()}
  def finalize_result(%__MODULE__{phase: :finalizing} = state, result) do
    with {:ok, transition} <- Class1.Receiver.finalize_result(state.core, result) do
      apply_core_transition(state, nil, transition)
    end
  end

  def finalize_result(%__MODULE__{} = state, result),
    do: {:error, {:unexpected_finalize_result, state.phase, result}}

  @spec file_effect_failed(t(), term()) :: {:ok, Transition.t(t())} | {:error, term()}
  def file_effect_failed(%__MODULE__{phase: phase} = state, reason)
      when phase in [:receiving, :waiting_repair, :verifying, :finalizing] do
    with {:ok, transition} <- Class1.Receiver.file_effect_failed(state.core, reason) do
      apply_core_transition(state, nil, transition)
    end
  end

  def file_effect_failed(%__MODULE__{} = state, reason),
    do: {:error, {:unexpected_file_effect_failure, state.phase, reason}}

  @doc """
  Issues an asynchronous NAK sequence in response to a caller-owned event.

  This operation is valid before initial receipt of EOF and emits a NAK even
  when no metadata or file-data requests are currently needed.
  """
  @spec request_nak(t()) :: {:ok, Transition.t(t())} | {:error, term()}
  def request_nak(%__MODULE__{suspended?: true}), do: {:error, :transaction_suspended}

  def request_nak(%__MODULE__{core: %{transaction_id: nil}}),
    do: {:error, :transaction_not_started}

  def request_nak(%__MODULE__{core: %{eof: %EndOfFile{}}}), do: {:error, :eof_already_received}

  def request_nak(%__MODULE__{} = state),
    do: {:ok, Transition.new(state, pdus: [nak_pdu(state)])}

  @spec timer_expired(t(), Transition.timer()) :: {:ok, Transition.t(t())} | {:error, term()}
  def timer_expired(%__MODULE__{suspended?: true}, timer),
    do: {:error, {:transaction_suspended, timer}}

  def timer_expired(%__MODULE__{phase: :waiting_repair} = state, :nak) do
    expirations = state.nak_expirations + 1

    if expirations >= state.nak_limit do
      fault(%{state | nak_expirations: expirations}, :nak_limit_reached, :nak)
    else
      state = %{state | nak_expirations: expirations}

      {:ok,
       Transition.new(state,
         pdus: [nak_pdu(state)],
         timers: [{:start, :nak}]
       )}
    end
  end

  def timer_expired(%__MODULE__{phase: :waiting_finished_ack} = state, :positive_ack) do
    expirations = state.positive_ack_expirations + 1

    if expirations >= state.positive_ack_limit do
      fault(
        %{state | positive_ack_expirations: expirations},
        :positive_ack_limit_reached,
        :positive_ack
      )
    else
      state = %{state | positive_ack_expirations: expirations}

      {:ok,
       Transition.new(state,
         pdus: [state.last_finished_pdu],
         timers: [{:start, :positive_ack}]
       )}
    end
  end

  def timer_expired(%__MODULE__{} = state, timer),
    do: {:error, {:unexpected_timer_expiration, state.phase, timer}}

  @spec suspend(t(), CFDP.condition()) :: {:ok, Transition.t(t())} | {:error, term()}
  def suspend(state, condition \\ :suspend_request_received)

  def suspend(%__MODULE__{core: %{transaction_id: nil}}, _condition),
    do: {:error, :transaction_not_started}

  def suspend(%__MODULE__{phase: phase}, _condition) when phase in [:completed, :faulted],
    do: {:error, {:transaction_terminal, phase}}

  def suspend(%__MODULE__{suspended?: true} = state, _condition),
    do: {:ok, Transition.new(state)}

  def suspend(%__MODULE__{} = state, condition) do
    state = %{state | suspended?: true}
    indication = Indication.new(:suspended, state.core.transaction_id, %{condition: condition})

    timers =
      case state.phase do
        :waiting_repair -> [{:cancel, :nak}]
        :waiting_finished_ack -> [{:cancel, :positive_ack}]
        _phase -> []
      end

    {:ok, Transition.new(state, indications: [indication], timers: timers)}
  end

  @spec resume(t()) :: {:ok, Transition.t(t())} | {:error, term()}
  def resume(%__MODULE__{suspended?: false}), do: {:error, :transaction_not_suspended}

  def resume(%__MODULE__{} = state) do
    state = %{state | suspended?: false, core: %{state.core | suspended?: false}}

    indication =
      Indication.new(:resumed, state.core.transaction_id, %{
        progress: Class1.Receiver.progress(state.core)
      })

    {pdus, timers} =
      case state.phase do
        :waiting_repair -> {[nak_pdu(state)], [{:start, :nak}]}
        :waiting_finished_ack -> {[state.last_finished_pdu], [{:start, :positive_ack}]}
        _phase -> {[], []}
      end

    {:ok, Transition.new(state, pdus: pdus, indications: [indication], timers: timers)}
  end

  @spec missing_ranges(t()) :: [{non_neg_integer(), non_neg_integer()}]
  def missing_ranges(%__MODULE__{} = state) do
    metadata_request = if(state.core.metadata, do: [], else: [{0, 0}])
    end_of_scope = end_of_scope(state)
    metadata_request ++ Class1.Receiver.missing_ranges(state.core, end_of_scope)
  end

  defp apply_core_transition(state, payload, core_transition, gap_detected? \\ false) do
    state = %{state | core: core_transition.state}
    nonterminal = Enum.reject(core_transition.indications, &terminal_indication?/1)
    terminal = Enum.find(core_transition.indications, &terminal_indication?/1)
    kind = core_transition_kind(core_transition, payload)

    apply_core_transition_kind(
      kind,
      state,
      payload,
      terminal,
      nonterminal,
      core_transition,
      gap_detected?
    )
  end

  defp core_transition_kind(core_transition, payload) do
    cond do
      Enum.any?(core_transition.indications, &(&1.type == :abandoned)) -> :abandoned
      core_transition.state.phase in [:completed, :faulted] -> :terminal
      Enum.any?(core_transition.indications, &(&1.type == :suspended)) -> :suspended
      core_transition.state.phase in [:verifying, :finalizing] -> :file_effect
      match?(%EndOfFile{}, payload) -> :incomplete_eof
      true -> :active
    end
  end

  defp apply_core_transition_kind(
         :abandoned,
         state,
         _payload,
         _terminal,
         _nonterminal,
         core_transition,
         _gap_detected?
       ) do
    state = %{state | phase: :faulted}

    {:ok,
     Transition.new(state,
       indications: core_transition.indications,
       timers: class2_timers(core_transition.timers),
       effects: core_transition.effects
     )}
  end

  defp apply_core_transition_kind(
         :terminal,
         state,
         payload,
         terminal,
         nonterminal,
         core_transition,
         _gap_detected?
       ),
       do: finish_from_core(state, payload, terminal, nonterminal, core_transition)

  defp apply_core_transition_kind(
         :suspended,
         state,
         _payload,
         _terminal,
         nonterminal,
         core_transition,
         _gap_detected?
       ) do
    state = %{state | suspended?: true}

    {:ok,
     Transition.new(state,
       indications: nonterminal,
       timers: class2_timers(core_transition.timers),
       effects: core_transition.effects
     )}
  end

  defp apply_core_transition_kind(
         :file_effect,
         state,
         payload,
         _terminal,
         nonterminal,
         core_transition,
         _gap_detected?
       ) do
    acknowledgement = if(match?(%EndOfFile{}, payload), do: [eof_ack(state, payload)], else: [])
    state = %{state | phase: core_transition.state.phase}

    {:ok,
     Transition.new(state,
       pdus: acknowledgement,
       indications: nonterminal,
       timers: class2_timers(core_transition.timers),
       effects: core_transition.effects
     )}
  end

  defp apply_core_transition_kind(
         :incomplete_eof,
         state,
         payload,
         _terminal,
         nonterminal,
         core_transition,
         _gap_detected?
       ) do
    acknowledgement = eof_ack(state, payload)
    state = %{state | phase: :waiting_repair}

    {pdus, timers} =
      if state.suspended? do
        {[acknowledgement], []}
      else
        {[acknowledgement, nak_pdu(state)], [{:start, :nak}]}
      end

    {:ok,
     Transition.new(state,
       pdus: pdus,
       indications: nonterminal,
       timers: timers,
       effects: core_transition.effects
     )}
  end

  defp apply_core_transition_kind(
         :active,
         state,
         _payload,
         _terminal,
         nonterminal,
         core_transition,
         gap_detected?
       ) do
    pdus =
      if state.immediate_nak? and gap_detected? and not state.suspended?,
        do: [nak_pdu(state)],
        else: []

    {:ok,
     Transition.new(state,
       pdus: pdus,
       indications: nonterminal,
       timers: class2_timers(core_transition.timers),
       effects: core_transition.effects
     )}
  end

  defp finish_from_core(state, payload, terminal, nonterminal, core_transition) do
    condition = terminal.details.condition
    delivery_code = if(condition == :no_error, do: :complete, else: :incomplete)
    fault_location = fault_location(state, condition)

    finished = %Finished{
      condition: condition,
      delivery_code: delivery_code,
      file_status: :unreported,
      fault_location: fault_location
    }

    finished_pdu = transaction_pdu(state, finished, :toward_file_sender)
    acknowledgement = if(match?(%EndOfFile{}, payload), do: [eof_ack(state, payload)], else: [])
    cancel_nak = if(state.phase == :waiting_repair, do: [{:cancel, :nak}], else: [])

    state = %{
      state
      | phase: :waiting_finished_ack,
        last_finished_pdu: finished_pdu,
        pending_indication: terminal
    }

    {finished_pdus, positive_ack_timer} =
      if state.suspended?, do: {[], []}, else: {[finished_pdu], [{:start, :positive_ack}]}

    {:ok,
     Transition.new(state,
       pdus: acknowledgement ++ finished_pdus,
       indications: nonterminal,
       timers: class2_timers(core_transition.timers) ++ cancel_nak ++ positive_ack_timer,
       effects: core_transition.effects
     )}
  end

  defp finish_with_fault(state, condition) do
    indication =
      Indication.new(:transaction_fault, state.core.transaction_id, %{condition: condition})

    finished = %Finished{
      condition: condition,
      delivery_code: :incomplete,
      file_status: :unreported,
      fault_location: fault_location(state, condition)
    }

    finished_pdu = transaction_pdu(state, finished, :toward_file_sender)

    state = %{
      state
      | phase: :waiting_finished_ack,
        last_finished_pdu: finished_pdu,
        pending_indication: indication
    }

    {:ok,
     Transition.new(state,
       pdus: [finished_pdu],
       timers: [{:cancel, :nak}, {:start, :positive_ack}]
     )}
  end

  defp eof_ack(state, %EndOfFile{} = eof) do
    transaction_pdu(
      state,
      %Acknowledgement{
        directive: :end_of_file,
        condition: eof.condition,
        transaction_status: :active
      },
      :toward_file_sender
    )
  end

  defp nak_pdu(state) do
    transaction_pdu(
      state,
      %NegativeAcknowledgement{
        start_of_scope: 0,
        end_of_scope: end_of_scope(state),
        segment_requests: missing_ranges(state)
      },
      :toward_file_sender
    )
  end

  defp end_of_scope(%__MODULE__{core: %{eof: %EndOfFile{file_size: size}}}), do: size
  defp end_of_scope(state), do: Class1.Receiver.extent(state.core)

  defp fault_location(_state, condition)
       when condition in [:no_error, :unsupported_checksum_type],
       do: nil

  defp fault_location(state, _condition),
    do: %EntityID{entity_id: state.core.local_entity_id}

  defp terminal_indication?(indication),
    do: indication.type in [:transaction_finished, :transaction_fault]

  defp validate_initial_or_bound(%__MODULE__{core: %{transaction_id: nil}} = state, pdu) do
    if pdu.transmission_mode == :acknowledged and
         pdu.direction == :toward_file_receiver and
         pdu.destination_entity_id == state.core.local_entity_id,
       do: :ok,
       else: {:error, {:invalid_initial_class2_pdu, pdu}}
  end

  defp validate_initial_or_bound(state, pdu),
    do: validate_incoming(state, pdu, :toward_file_receiver)

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

  defp unacknowledged(%PDU{} = pdu), do: %{pdu | transmission_mode: :unacknowledged}

  defp prompt_transition(%__MODULE__{suspended?: true} = state, _prompt),
    do: {:ok, Transition.new(state)}

  defp prompt_transition(state, %Prompt{response: :nak}),
    do: {:ok, Transition.new(state, pdus: [nak_pdu(state)])}

  defp prompt_transition(state, %Prompt{response: :keep_alive}) do
    keep_alive =
      transaction_pdu(
        state,
        %KeepAlive{progress: Class1.Receiver.progress(state.core)},
        :toward_file_sender
      )

    {:ok, Transition.new(state, pdus: [keep_alive])}
  end

  defp validate_limit(value, _field) when is_integer(value) and value > 0, do: :ok
  defp validate_limit(value, field), do: {:error, {:invalid_field, field, value}}

  defp validate_boolean(value, _field) when is_boolean(value), do: :ok
  defp validate_boolean(value, field), do: {:error, {:invalid_field, field, value}}

  defp gap_detected?(state, %FileData{offset: offset}) when is_integer(offset),
    do: state.core.eof == nil and offset > Class1.Receiver.progress(state.core)

  defp gap_detected?(_state, _payload), do: false

  defp class2_timers(timers), do: Enum.reject(timers, &match?({_action, :check}, &1))

  defp fault(state, condition, timer) do
    options = if(state.core.metadata, do: state.core.metadata.options, else: [])

    case FaultPolicy.handler(state.core.fault_policy, condition, options) do
      :cancel -> finish_with_fault(state, condition)
      :abandon -> abandon(state, condition, timer)
      :suspend -> suspend(state, condition)
      :ignore -> ignore_fault(state, condition, timer)
    end
  end

  defp abandon(state, condition, timer) do
    state = %{state | phase: :faulted}

    indication =
      Indication.new(:abandoned, state.core.transaction_id, %{
        condition: condition,
        progress: Class1.Receiver.progress(state.core)
      })

    {:ok, Transition.new(state, indications: [indication], timers: [{:cancel, timer}])}
  end

  defp ignore_fault(state, condition, timer) do
    indication =
      Indication.new(:fault, state.core.transaction_id, %{
        condition: condition,
        progress: Class1.Receiver.progress(state.core)
      })

    {:ok,
     Transition.new(state,
       indications: [indication],
       timers: [{:start, timer}]
     )}
  end
end
