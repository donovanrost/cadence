defmodule Cadence.CCSDS.CFDP.Class1.Receiver do
  @moduledoc """
  Pure Class 1 (unacknowledged) receiving procedure.

  File segments may arrive out of order. Equal retransmissions are idempotent;
  conflicting overlaps produce an invalid-file-structure fault. Transaction
  closure and the Check procedure are represented as PDUs and caller-owned
  timer effects.

  By default, data is assembled in memory. Passing a `sink` reference to
  `new/2` instead emits ordered write, checksum, finalize, and discard effects;
  the file bytes are then never retained by the transaction state.
  """

  alias Cadence.CCSDS.CFDP

  alias Cadence.CCSDS.CFDP.{
    Checksum,
    Configuration,
    FaultPolicy,
    FileData,
    FileEffect,
    Indication,
    PDU,
    RangeSet,
    SegmentStore,
    Transaction,
    TransactionID,
    Transition
  }

  alias Cadence.CCSDS.CFDP.Directive.{EndOfFile, Finished, Metadata}
  alias Cadence.CCSDS.CFDP.TLV.EntityID

  @type phase :: :receiving | :checking | :verifying | :finalizing | :completed | :faulted

  @type t :: %__MODULE__{
          local_entity_id: non_neg_integer(),
          transaction_id: TransactionID.t() | nil,
          destination_entity_id: non_neg_integer(),
          transmission_mode: :unacknowledged,
          crc?: boolean(),
          large_file?: boolean(),
          entity_id_octets: 1..8 | nil,
          sequence_number_octets: 1..8 | nil,
          metadata: Metadata.t() | nil,
          eof: EndOfFile.t() | nil,
          segments: SegmentStore.t(),
          ranges: RangeSet.t(),
          sink: term(),
          checksum_provider: module() | nil,
          phase: phase(),
          check_expirations: non_neg_integer(),
          check_limit: pos_integer(),
          fault_policy: FaultPolicy.t(),
          suspension_allowed?: boolean(),
          suspended?: boolean()
        }

  @enforce_keys [:local_entity_id]
  defstruct local_entity_id: nil,
            transaction_id: nil,
            destination_entity_id: nil,
            transmission_mode: :unacknowledged,
            crc?: false,
            large_file?: false,
            entity_id_octets: nil,
            sequence_number_octets: nil,
            metadata: nil,
            eof: nil,
            segments: [],
            ranges: [],
            sink: nil,
            checksum_provider: nil,
            phase: :receiving,
            check_expirations: 0,
            check_limit: 1,
            fault_policy: nil,
            suspension_allowed?: false,
            suspended?: false

  @spec new(non_neg_integer(), keyword()) :: {:ok, t()} | {:error, term()}
  def new(local_entity_id, opts \\ []) when is_list(opts) do
    configuration = Keyword.get(opts, :configuration, Configuration.new!())
    check_limit = Keyword.get(opts, :check_limit, 1)
    fault_policy = Keyword.get(opts, :fault_policy, FaultPolicy.new!())

    cond do
      not valid_identifier?(local_entity_id) ->
        {:error, {:invalid_local_entity_id, local_entity_id}}

      not match?(%Configuration{}, configuration) ->
        {:error, {:invalid_cfdp_configuration, configuration}}

      Configuration.validate(configuration) != :ok ->
        Configuration.validate(configuration)

      FaultPolicy.validate(fault_policy) != :ok ->
        FaultPolicy.validate(fault_policy)

      not is_integer(check_limit) or check_limit <= 0 ->
        {:error, {:invalid_field, :check_limit, check_limit}}

      true ->
        {:ok,
         %__MODULE__{
           local_entity_id: local_entity_id,
           checksum_provider: Keyword.get(opts, :checksum_provider),
           sink: if(Keyword.has_key?(opts, :sink), do: {:external, Keyword.get(opts, :sink)}),
           check_limit: check_limit,
           fault_policy: fault_policy,
           suspension_allowed?: Keyword.get(opts, :suspension_allowed?, false)
         }}
    end
  end

  @spec ingest(t(), PDU.t()) :: {:ok, Transition.t(t())} | {:error, term()}
  def ingest(%__MODULE__{phase: phase}, %PDU{}) when phase in [:completed, :faulted],
    do: {:error, {:transaction_terminal, phase}}

  def ingest(%__MODULE__{} = state, %PDU{} = pdu) do
    with {:ok, state, started} <- bind_transaction(state, pdu),
         :ok <- Transaction.validate_incoming(pdu, state, :toward_file_receiver) do
      case accept_payload(state, pdu.payload) do
        {:ok, state, indications, effects} ->
          maybe_complete(state, started ++ indications, effects)

        {:error, reason}
        when reason in [:invalid_file_structure, :conflicting_metadata_pdu, :conflicting_eof_pdu] ->
          fault(state, :invalid_file_structure, started)

        {:error, _reason} = error ->
          error
      end
    end
  end

  def ingest(%__MODULE__{}, value), do: {:error, {:invalid_cfdp_pdu, value}}

  @spec checksum_result(t(), {:ok, 0..0xFFFFFFFF} | {:error, term()}) ::
          {:ok, Transition.t(t())} | {:error, term()}
  def checksum_result(%__MODULE__{phase: :verifying} = state, {:ok, checksum})
      when is_integer(checksum) and checksum in 0..0xFFFFFFFF do
    if checksum == state.eof.file_checksum do
      state = %{state | phase: :finalizing}

      effect =
        FileEffect.new(:finalize, sink_reference(state), state.transaction_id,
          length: state.eof.file_size,
          details: %{destination_file_name: state.metadata.destination_file_name}
        )

      {:ok, Transition.new(state, effects: [effect])}
    else
      fault(state, :file_checksum_failure, [])
    end
  end

  def checksum_result(%__MODULE__{phase: :verifying} = state, {:error, :unsupported}),
    do: fault(state, :unsupported_checksum_type, [])

  def checksum_result(%__MODULE__{phase: :verifying} = state, {:error, _reason}),
    do: fault(state, :filestore_rejection, [])

  def checksum_result(%__MODULE__{} = state, result),
    do: {:error, {:unexpected_checksum_result, state.phase, result}}

  @spec finalize_result(t(), :ok | {:error, term()}) ::
          {:ok, Transition.t(t())} | {:error, term()}
  def finalize_result(%__MODULE__{phase: :finalizing} = state, :ok),
    do: finish_successfully(state, nil, [])

  def finalize_result(%__MODULE__{phase: :finalizing} = state, {:error, _reason}),
    do: fault(state, :filestore_rejection, [])

  def finalize_result(%__MODULE__{} = state, result),
    do: {:error, {:unexpected_finalize_result, state.phase, result}}

  @spec file_effect_failed(t(), term()) :: {:ok, Transition.t(t())}
  def file_effect_failed(%__MODULE__{} = state, reason),
    do: fault(state, :filestore_rejection, [], %{file_error: reason})

  @spec timer_expired(t(), Transition.timer()) :: {:ok, Transition.t(t())} | {:error, term()}
  def timer_expired(%__MODULE__{suspended?: true}, timer),
    do: {:error, {:transaction_suspended, timer}}

  def timer_expired(%__MODULE__{phase: :checking} = state, :check) do
    case completion_condition(state) do
      :ready ->
        complete(state, [], [])

      _incomplete ->
        expirations = state.check_expirations + 1

        if expirations >= state.check_limit do
          fault(%{state | check_expirations: expirations}, :check_limit_reached, [])
        else
          state = %{state | check_expirations: expirations}
          {:ok, Transition.new(state, timers: [{:start, :check}])}
        end
    end
  end

  def timer_expired(%__MODULE__{} = state, timer),
    do: {:error, {:unexpected_timer_expiration, state.phase, timer}}

  @spec suspend(t(), CFDP.condition()) :: {:ok, Transition.t(t())} | {:error, term()}
  def suspend(state, condition \\ :suspend_request_received)

  def suspend(%__MODULE__{suspension_allowed?: false}, _condition),
    do: {:error, :receiver_suspension_requires_acknowledged_mode}

  def suspend(%__MODULE__{transaction_id: nil}, _condition),
    do: {:error, :transaction_not_started}

  def suspend(%__MODULE__{phase: phase}, _condition)
      when phase in [:completed, :faulted],
      do: {:error, {:transaction_terminal, phase}}

  def suspend(%__MODULE__{suspended?: true} = state, _condition),
    do: {:ok, Transition.new(state)}

  def suspend(%__MODULE__{} = state, condition) do
    state = %{state | suspended?: true}
    indication = Indication.new(:suspended, state.transaction_id, %{condition: condition})
    timers = if(state.phase == :checking, do: [{:cancel, :check}], else: [])
    {:ok, Transition.new(state, indications: [indication], timers: timers)}
  end

  @spec resume(t()) :: {:ok, Transition.t(t())} | {:error, term()}
  def resume(%__MODULE__{suspended?: false}), do: {:error, :transaction_not_suspended}

  def resume(%__MODULE__{} = state) do
    state = %{state | suspended?: false}
    indication = Indication.new(:resumed, state.transaction_id, %{progress: progress(state)})
    timers = if(state.phase == :checking, do: [{:start, :check}], else: [])
    {:ok, Transition.new(state, indications: [indication], timers: timers)}
  end

  defp bind_transaction(%__MODULE__{transaction_id: nil} = state, pdu) do
    if pdu.transmission_mode == :unacknowledged and
         pdu.direction == :toward_file_receiver and
         pdu.destination_entity_id == state.local_entity_id do
      state = %{
        state
        | transaction_id: Transaction.id(pdu),
          destination_entity_id: pdu.destination_entity_id,
          crc?: pdu.crc?,
          large_file?: pdu.large_file?,
          entity_id_octets: pdu.entity_id_octets,
          sequence_number_octets: pdu.sequence_number_octets
      }

      indication =
        Indication.new(:transaction_started, state.transaction_id, %{
          transmission_mode: :unacknowledged
        })

      {:ok, state, [indication]}
    else
      {:error, {:invalid_initial_class1_pdu, pdu}}
    end
  end

  defp bind_transaction(%__MODULE__{} = state, _pdu), do: {:ok, state, []}

  defp accept_payload(%__MODULE__{metadata: nil} = state, %Metadata{} = metadata) do
    indication =
      Indication.new(:metadata_received, state.transaction_id, %{
        source_file_name: metadata.source_file_name,
        destination_file_name: metadata.destination_file_name,
        file_size: metadata.file_size,
        options: metadata.options
      })

    {:ok, %{state | metadata: metadata}, [indication], []}
  end

  defp accept_payload(%__MODULE__{metadata: metadata} = state, %Metadata{} = metadata),
    do: {:ok, state, [], []}

  defp accept_payload(%__MODULE__{}, %Metadata{}),
    do: {:error, :conflicting_metadata_pdu}

  defp accept_payload(%__MODULE__{sink: {:external, _reference}} = state, %FileData{} = file_data) do
    with {:ok, ranges} <- RangeSet.put(state.ranges, file_data.offset, byte_size(file_data.data)) do
      indication = file_segment_indication(state, file_data)

      effect =
        FileEffect.new(:write, sink_reference(state), state.transaction_id,
          offset: file_data.offset,
          length: byte_size(file_data.data),
          data: file_data.data
        )

      {:ok, %{state | ranges: ranges}, [indication], [effect]}
    end
  end

  defp accept_payload(state, %FileData{} = file_data) do
    case SegmentStore.put(state.segments, file_data.offset, file_data.data) do
      {:ok, segments} ->
        indication = file_segment_indication(state, file_data)

        {:ok, %{state | segments: segments}, [indication], []}

      {:error, {:conflicting_file_segment, _offset, _length}} ->
        {:error, :invalid_file_structure}

      {:error, _reason} = error ->
        error
    end
  end

  defp accept_payload(%__MODULE__{eof: nil} = state, %EndOfFile{} = eof) do
    indication =
      Indication.new(:eof_received, state.transaction_id, %{
        condition: eof.condition,
        file_size: eof.file_size
      })

    {:ok, %{state | eof: eof}, [indication], []}
  end

  defp accept_payload(%__MODULE__{eof: eof} = state, %EndOfFile{} = eof),
    do: {:ok, state, [], []}

  defp accept_payload(%__MODULE__{}, %EndOfFile{}), do: {:error, :conflicting_eof_pdu}

  defp accept_payload(_state, payload),
    do: {:error, {:unexpected_class1_receiver_payload, payload}}

  defp maybe_complete(%__MODULE__{eof: nil} = state, indications, effects),
    do: {:ok, Transition.new(state, indications: indications, effects: effects)}

  defp maybe_complete(
         %__MODULE__{eof: %EndOfFile{condition: condition}} = state,
         indications,
         effects
       )
       when condition != :no_error,
       do: fault(state, condition, indications, %{}, effects)

  defp maybe_complete(state, indications, effects) do
    case completion_condition(state) do
      :ready ->
        complete(state, indications, effects)

      _incomplete ->
        timers = if(state.phase == :checking, do: [], else: [{:start, :check}])

        {:ok,
         Transition.new(%{state | phase: :checking},
           indications: indications,
           timers: timers,
           effects: effects
         )}
    end
  end

  defp completion_condition(%__MODULE__{metadata: nil}), do: :metadata_missing
  defp completion_condition(%__MODULE__{eof: nil}), do: :eof_missing

  defp completion_condition(state) do
    if coverage_complete?(state, state.eof.file_size),
      do: :ready,
      else: :file_data_missing
  end

  defp complete(%__MODULE__{sink: {:external, _reference}} = state, indications, effects) do
    case validate_received_size(state) do
      :ok -> request_checksum(state, indications, effects)
      {:error, :file_size_error} -> fault(state, :file_size_error, indications, %{}, effects)
    end
  end

  defp complete(state, indications, effects) do
    with :ok <- validate_received_size(state),
         {:ok, file} <- SegmentStore.assemble(state.segments, state.eof.file_size),
         {:ok, checksum} <-
           Checksum.compute(state.metadata.checksum_type, file, provider: state.checksum_provider) do
      finish_for_checksum(state, file, checksum, indications, effects)
    else
      {:error, :file_size_error} ->
        fault(state, :file_size_error, indications, %{}, effects)

      {:error, {:unsupported_checksum_type, _type}} ->
        fault(state, :unsupported_checksum_type, indications, %{}, effects)

      {:error, _reason} = error ->
        error
    end
  end

  defp request_checksum(state, indications, effects) do
    checking? = state.phase == :checking
    state = %{state | phase: :verifying}

    effect =
      FileEffect.new(:checksum, sink_reference(state), state.transaction_id,
        length: state.eof.file_size,
        details: %{
          checksum_type: state.metadata.checksum_type,
          expected_checksum: state.eof.file_checksum
        }
      )

    {:ok,
     Transition.new(state,
       indications: indications,
       timers: if(checking?, do: [{:cancel, :check}], else: []),
       effects: effects ++ [effect]
     )}
  end

  defp validate_received_size(state) do
    metadata_size_valid? = state.metadata.file_size in [0, state.eof.file_size]
    extent_valid? = coverage_extent(state) <= state.eof.file_size

    if metadata_size_valid? and extent_valid?, do: :ok, else: {:error, :file_size_error}
  end

  defp finish_for_checksum(state, file, checksum, indications, effects) do
    if checksum == state.eof.file_checksum,
      do: finish_successfully(state, file, indications, effects),
      else: fault(state, :file_checksum_failure, indications, %{}, effects)
  end

  defp finish_successfully(state, file, indications, effects \\ []) do
    checking? = state.phase == :checking
    state = %{state | phase: :completed}

    finished =
      if state.metadata.closure_requested? do
        [
          Transaction.pdu(
            state,
            %Finished{
              condition: :no_error,
              delivery_code: :complete,
              file_status: :unreported
            },
            :toward_file_sender
          )
        ]
      else
        []
      end

    details = %{
      condition: :no_error,
      delivery_code: :complete,
      destination_file_name: state.metadata.destination_file_name
    }

    details = if(is_binary(file), do: Map.put(details, :file, file), else: details)
    indication = Indication.new(:transaction_finished, state.transaction_id, details)

    {:ok,
     Transition.new(state,
       pdus: finished,
       indications: indications ++ [indication],
       timers: if(checking?, do: [{:cancel, :check}], else: []),
       effects: effects
     )}
  end

  defp fault(state, condition, indications, details \\ %{}, effects \\ []) do
    options = if(state.metadata, do: state.metadata.options, else: [])

    case FaultPolicy.handler(state.fault_policy, condition, options) do
      :cancel -> cancel_fault(state, condition, indications, details, effects)
      :abandon -> abandon(state, condition, indications, details, effects)
      :ignore -> ignore_fault(state, condition, indications, details, effects)
      :suspend -> suspend_fault(state, condition, indications, details, effects)
    end
  end

  defp cancel_fault(state, condition, indications, details, effects) do
    checking? = state.phase == :checking
    state = %{state | phase: :faulted}
    closure_requested? = state.metadata && state.metadata.closure_requested?

    finished =
      if closure_requested? do
        fault_location =
          if condition in [:no_error, :unsupported_checksum_type],
            do: nil,
            else: %EntityID{entity_id: state.local_entity_id}

        [
          Transaction.pdu(
            state,
            %Finished{
              condition: condition,
              delivery_code: :incomplete,
              file_status: :unreported,
              fault_location: fault_location
            },
            :toward_file_sender
          )
        ]
      else
        []
      end

    indication =
      Indication.new(
        :transaction_fault,
        state.transaction_id,
        Map.put(details, :condition, condition)
      )

    {:ok,
     Transition.new(state,
       pdus: finished,
       indications: indications ++ [indication],
       timers: if(checking?, do: [{:cancel, :check}], else: []),
       effects: effects ++ discard_effect(state, condition)
     )}
  end

  defp abandon(state, condition, indications, details, effects) do
    checking? = state.phase == :checking
    state = %{state | phase: :faulted}

    indication =
      Indication.new(
        :abandoned,
        state.transaction_id,
        details
        |> Map.put(:condition, condition)
        |> Map.put(:progress, progress(state))
      )

    {:ok,
     Transition.new(state,
       indications: indications ++ [indication],
       timers: if(checking?, do: [{:cancel, :check}], else: []),
       effects: effects ++ discard_effect(state, condition)
     )}
  end

  defp ignore_fault(state, condition, indications, details, effects) do
    indication =
      Indication.new(
        :fault,
        state.transaction_id,
        details
        |> Map.put(:condition, condition)
        |> Map.put(:progress, progress(state))
      )

    timers = if(state.phase == :checking, do: [{:start, :check}], else: [])

    {:ok,
     Transition.new(state,
       indications: indications ++ [indication],
       timers: timers,
       effects: effects
     )}
  end

  defp suspend_fault(
         %__MODULE__{suspension_allowed?: true} = state,
         condition,
         indications,
         _details,
         effects
       ) do
    with {:ok, transition} <- suspend(state, condition) do
      {:ok,
       %Transition{
         transition
         | indications: indications ++ transition.indications,
           effects: effects,
           state: transition.state
       }}
    end
  end

  defp suspend_fault(state, condition, indications, details, effects),
    do:
      ignore_fault(
        state,
        condition,
        indications,
        Map.put(details, :suspension_ignored?, true),
        effects
      )

  @spec progress(t()) :: non_neg_integer()
  def progress(%__MODULE__{sink: {:external, _reference}} = state),
    do: RangeSet.progress(state.ranges)

  def progress(%__MODULE__{} = state), do: SegmentStore.progress(state.segments)

  @spec extent(t()) :: non_neg_integer()
  def extent(%__MODULE__{sink: {:external, _reference}} = state),
    do: RangeSet.extent(state.ranges)

  def extent(%__MODULE__{} = state), do: SegmentStore.extent(state.segments)

  @spec missing_ranges(t(), non_neg_integer()) ::
          [{non_neg_integer(), non_neg_integer()}]
  def missing_ranges(%__MODULE__{sink: {:external, _reference}} = state, end_offset),
    do: RangeSet.missing(state.ranges, 0, end_offset)

  def missing_ranges(%__MODULE__{} = state, end_offset),
    do: SegmentStore.missing(state.segments, 0, end_offset)

  defp file_segment_indication(state, file_data) do
    Indication.new(:file_segment_received, state.transaction_id, %{
      offset: file_data.offset,
      length: byte_size(file_data.data)
    })
  end

  defp coverage_complete?(%__MODULE__{sink: {:external, _reference}} = state, size),
    do: RangeSet.complete?(state.ranges, size)

  defp coverage_complete?(state, size), do: SegmentStore.complete?(state.segments, size)

  defp coverage_extent(%__MODULE__{sink: {:external, _reference}} = state),
    do: RangeSet.extent(state.ranges)

  defp coverage_extent(state), do: SegmentStore.extent(state.segments)

  defp sink_reference(%__MODULE__{sink: {:external, reference}}), do: reference

  defp discard_effect(%__MODULE__{sink: {:external, reference}} = state, condition) do
    [FileEffect.new(:discard, reference, state.transaction_id, details: %{condition: condition})]
  end

  defp discard_effect(_state, _condition), do: []

  defp valid_identifier?(value),
    do: is_integer(value) and value >= 0 and value <= 0xFFFFFFFFFFFFFFFF
end
