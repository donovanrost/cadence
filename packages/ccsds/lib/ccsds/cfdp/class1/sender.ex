defmodule CCSDS.CFDP.Class1.Sender do
  @moduledoc """
  Pure Class 1 (unacknowledged) sending procedure.

  `next/1` emits one Metadata, File Data, or EOF PDU at a time. The caller owns
  encoding, transport, timer scheduling, and any durable transaction record.
  A binary `file` is a convenience; a caller can instead supply `source`,
  `file_size`, and `file_checksum`, then satisfy emitted read effects with
  `supply_read/2` without retaining the file in the transaction process.
  """

  alias CCSDS.CFDP

  alias CCSDS.CFDP.{
    Checksum,
    Configuration,
    FaultPolicy,
    FileData,
    FileEffect,
    Indication,
    PDU,
    Transaction,
    TransactionID,
    Transition
  }

  alias CCSDS.CFDP.Directive.{EndOfFile, Finished, Metadata}

  @type phase ::
          :ready
          | :sending_data
          | :awaiting_read
          | :eof
          | :waiting_finished
          | :completed
          | :faulted

  @type t :: %__MODULE__{
          transaction_id: TransactionID.t(),
          destination_entity_id: non_neg_integer(),
          source_file_name: binary(),
          destination_file_name: binary(),
          file: binary() | nil,
          source: term(),
          file_size: non_neg_integer(),
          checksum_type: 0..15,
          file_checksum: 0..0xFFFFFFFF,
          options: list(),
          crc?: boolean(),
          large_file?: boolean(),
          entity_id_octets: 1..8 | nil,
          sequence_number_octets: 1..8 | nil,
          segment_octets: pos_integer(),
          closure_requested?: boolean(),
          phase: phase(),
          next_offset: non_neg_integer(),
          pending_read: {non_neg_integer(), pos_integer()} | nil,
          check_expirations: non_neg_integer(),
          check_limit: pos_integer(),
          fault_policy: FaultPolicy.t(),
          suspended?: boolean(),
          transmission_mode: :unacknowledged
        }

  @enforce_keys [:transaction_id, :destination_entity_id, :file_size, :file_checksum]
  defstruct transaction_id: nil,
            destination_entity_id: nil,
            source_file_name: <<>>,
            destination_file_name: <<>>,
            file: nil,
            source: nil,
            file_size: 0,
            checksum_type: 0,
            file_checksum: 0,
            options: [],
            crc?: false,
            large_file?: false,
            entity_id_octets: nil,
            sequence_number_octets: nil,
            segment_octets: 1_024,
            closure_requested?: false,
            phase: :ready,
            next_offset: 0,
            pending_read: nil,
            check_expirations: 0,
            check_limit: 1,
            fault_policy: nil,
            suspended?: false,
            transmission_mode: :unacknowledged

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = Map.new(attrs)
    configuration = Map.get(attrs, :configuration, Configuration.new!())
    checksum_type = Map.get(attrs, :checksum_type, 0)

    fault_policy = Map.get(attrs, :fault_policy, FaultPolicy.new!())

    with %Configuration{} <- configuration,
         :ok <- Configuration.validate(configuration),
         :ok <- FaultPolicy.validate(fault_policy),
         true <- checksum_type in configuration.valid_checksum_types,
         {:ok, file, source, file_size, checksum} <- source(attrs, checksum_type),
         {:ok, transaction_id} <- transaction_id(attrs),
         {:ok, destination} <- destination(attrs),
         {:ok, segment_octets} <- segment_octets(attrs, configuration),
         :ok <- validate_positive(Map.get(attrs, :check_limit, 1), :check_limit),
         :ok <- validate_boolean(Map.get(attrs, :closure_requested?, false), :closure_requested?),
         :ok <- validate_boolean(Map.get(attrs, :crc?, false), :crc?) do
      large_file? = Map.get(attrs, :large_file?, file_size > 0xFFFFFFFF)

      if not large_file? and file_size > 0xFFFFFFFF do
        {:error, {:file_requires_large_file_mode, file_size}}
      else
        {:ok,
         %__MODULE__{
           transaction_id: transaction_id,
           destination_entity_id: destination,
           source_file_name: Map.get(attrs, :source_file_name, <<>>),
           destination_file_name: Map.get(attrs, :destination_file_name, <<>>),
           file: file,
           source: source,
           file_size: file_size,
           checksum_type: checksum_type,
           file_checksum: checksum,
           options: Map.get(attrs, :options, []),
           crc?: Map.get(attrs, :crc?, false),
           large_file?: large_file?,
           entity_id_octets: fixed_width(configuration.entity_id_octets),
           sequence_number_octets: fixed_width(configuration.sequence_number_octets),
           segment_octets: segment_octets,
           closure_requested?: Map.get(attrs, :closure_requested?, false),
           check_limit: Map.get(attrs, :check_limit, 1),
           fault_policy: fault_policy
         }}
      end
    else
      false -> {:error, {:invalid_class1_sender_options, attrs}}
      {:error, _reason} = error -> error
      value -> {:error, {:invalid_cfdp_configuration, value}}
    end
  end

  @spec next(t()) :: {:ok, Transition.t(t())} | {:error, term()}
  def next(%__MODULE__{suspended?: true}), do: {:error, :transaction_suspended}

  def next(%__MODULE__{phase: :ready} = state) do
    metadata = %Metadata{
      closure_requested?: state.closure_requested?,
      checksum_type: state.checksum_type,
      file_size: state.file_size,
      source_file_name: state.source_file_name,
      destination_file_name: state.destination_file_name,
      options: state.options
    }

    phase = if(state.file_size == 0, do: :eof, else: :sending_data)
    state = %{state | phase: phase}

    indication =
      Indication.new(:transaction_started, state.transaction_id, %{
        file_size: state.file_size,
        transmission_mode: :unacknowledged
      })

    {:ok,
     Transition.new(state,
       pdus: [Transaction.pdu(state, metadata, :toward_file_receiver)],
       indications: [indication]
     )}
  end

  def next(%__MODULE__{phase: :sending_data, file: file} = state) when is_binary(file) do
    remaining = state.file_size - state.next_offset
    length = min(remaining, state.segment_octets)
    data = binary_part(file, state.next_offset, length)
    emit_segment(state, state.next_offset, data)
  end

  def next(%__MODULE__{phase: :sending_data} = state) do
    remaining = state.file_size - state.next_offset
    length = min(remaining, state.segment_octets)
    state = %{state | phase: :awaiting_read, pending_read: {state.next_offset, length}}

    effect =
      FileEffect.new(:read, state.source, state.transaction_id,
        offset: state.next_offset,
        length: length
      )

    {:ok, Transition.new(state, effects: [effect])}
  end

  def next(%__MODULE__{phase: :eof} = state) do
    eof = %EndOfFile{file_checksum: state.file_checksum, file_size: state.file_size}

    if state.closure_requested? do
      state = %{state | phase: :waiting_finished}

      {:ok,
       Transition.new(state,
         pdus: [Transaction.pdu(state, eof, :toward_file_receiver)],
         timers: [{:start, :check}]
       )}
    else
      state = %{state | phase: :completed}

      indication =
        Indication.new(:transaction_finished, state.transaction_id, %{
          condition: :no_error,
          delivery_code: :complete
        })

      {:ok,
       Transition.new(state,
         pdus: [Transaction.pdu(state, eof, :toward_file_receiver)],
         indications: [indication]
       )}
    end
  end

  def next(%__MODULE__{phase: phase}), do: {:error, {:no_pdu_available, phase}}

  @spec supply_read(t(), binary()) :: {:ok, Transition.t(t())} | {:error, term()}
  def supply_read(
        %__MODULE__{phase: :awaiting_read, pending_read: {offset, length}} = state,
        data
      )
      when is_binary(data) do
    if byte_size(data) == length do
      state = %{state | pending_read: nil}
      emit_segment(state, offset, data)
    else
      {:error, {:unexpected_file_read_length, offset, length, byte_size(data)}}
    end
  end

  def supply_read(%__MODULE__{} = state, data),
    do: {:error, {:unexpected_file_read_result, state.phase, data}}

  @spec ingest(t(), PDU.t()) :: {:ok, Transition.t(t())} | {:error, term()}
  def ingest(
        %__MODULE__{phase: :waiting_finished} = state,
        %PDU{payload: %Finished{} = finished} = pdu
      ) do
    with :ok <- Transaction.validate_incoming(pdu, state, :toward_file_sender) do
      phase = if(finished.condition == :no_error, do: :completed, else: :faulted)
      state = %{state | phase: phase}
      type = if(phase == :completed, do: :transaction_finished, else: :transaction_fault)

      indication =
        Indication.new(type, state.transaction_id, %{
          condition: finished.condition,
          delivery_code: finished.delivery_code,
          file_status: finished.file_status
        })

      {:ok,
       Transition.new(state,
         indications: [indication],
         timers: [{:cancel, :check}]
       )}
    end
  end

  def ingest(%__MODULE__{} = state, %PDU{} = pdu),
    do: {:error, {:unexpected_pdu, state.phase, pdu.payload}}

  @spec timer_expired(t(), Transition.timer()) :: {:ok, Transition.t(t())} | {:error, term()}
  def timer_expired(%__MODULE__{suspended?: true}, timer),
    do: {:error, {:transaction_suspended, timer}}

  def timer_expired(%__MODULE__{phase: :waiting_finished} = state, :check) do
    expirations = state.check_expirations + 1

    if expirations >= state.check_limit do
      fault(%{state | check_expirations: expirations}, :check_limit_reached)
    else
      state = %{state | check_expirations: expirations}
      {:ok, Transition.new(state, timers: [{:start, :check}])}
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

    indication =
      Indication.new(:suspended, state.transaction_id, %{condition: condition})

    timers = if(state.phase == :waiting_finished, do: [{:cancel, :check}], else: [])
    {:ok, Transition.new(state, indications: [indication], timers: timers)}
  end

  @spec resume(t()) :: {:ok, Transition.t(t())} | {:error, term()}
  def resume(%__MODULE__{suspended?: false}), do: {:error, :transaction_not_suspended}

  def resume(%__MODULE__{} = state) do
    state = %{state | suspended?: false}
    indication = Indication.new(:resumed, state.transaction_id, %{progress: state.next_offset})
    timers = if(state.phase == :waiting_finished, do: [{:start, :check}], else: [])
    {:ok, Transition.new(state, indications: [indication], timers: timers)}
  end

  defp transaction_id(attrs) do
    source = Map.get(attrs, :source_entity_id)
    sequence = Map.get(attrs, :transaction_sequence_number)

    if valid_identifier?(source) and valid_identifier?(sequence),
      do: {:ok, TransactionID.new(source, sequence)},
      else: {:error, {:invalid_transaction_id, source, sequence}}
  end

  defp source(attrs, checksum_type) do
    has_file? = Map.has_key?(attrs, :file)
    has_source? = Map.has_key?(attrs, :source)

    case {has_file?, has_source?} do
      {true, false} -> in_memory_source(attrs, checksum_type)
      {false, true} -> external_source(attrs)
      {true, true} -> {:error, :file_and_source_are_mutually_exclusive}
      {false, false} -> {:error, :file_or_source_required}
    end
  end

  defp in_memory_source(attrs, checksum_type) do
    file = Map.fetch!(attrs, :file)

    if is_binary(file) do
      case Checksum.compute(checksum_type, file, provider: Map.get(attrs, :checksum_provider)) do
        {:ok, checksum} -> {:ok, file, nil, byte_size(file), checksum}
        {:error, _reason} = error -> error
      end
    else
      {:error, {:invalid_field, :file, file}}
    end
  end

  defp external_source(attrs) do
    source = Map.fetch!(attrs, :source)
    file_size = Map.get(attrs, :file_size)
    checksum = Map.get(attrs, :file_checksum)

    with :ok <- validate_nonnegative(file_size, :file_size),
         :ok <- validate_checksum(checksum) do
      {:ok, nil, source, file_size, checksum}
    end
  end

  defp emit_segment(state, offset, data) do
    payload = %FileData{offset: offset, data: data}
    next_offset = offset + byte_size(data)
    phase = if(next_offset == state.file_size, do: :eof, else: :sending_data)
    state = %{state | next_offset: next_offset, phase: phase}

    {:ok, Transition.new(state, pdus: [Transaction.pdu(state, payload, :toward_file_receiver)])}
  end

  defp destination(attrs) do
    value = Map.get(attrs, :destination_entity_id)

    if valid_identifier?(value),
      do: {:ok, value},
      else: {:error, {:invalid_destination_entity_id, value}}
  end

  defp segment_octets(attrs, configuration) do
    maximum = configuration.maximum_pdu_data_octets - 8 - 2

    value =
      Map.get(attrs, :segment_octets, min(configuration.maximum_file_segment_octets, maximum))

    if is_integer(value) and value > 0 and value <= maximum,
      do: {:ok, value},
      else: {:error, {:invalid_segment_octets, value, maximum}}
  end

  defp valid_identifier?(value),
    do: is_integer(value) and value >= 0 and value <= 0xFFFFFFFFFFFFFFFF

  defp validate_positive(value, _field) when is_integer(value) and value > 0, do: :ok
  defp validate_positive(value, field), do: {:error, {:invalid_field, field, value}}

  defp validate_nonnegative(value, _field) when is_integer(value) and value >= 0, do: :ok
  defp validate_nonnegative(value, field), do: {:error, {:invalid_field, field, value}}

  defp validate_checksum(value) when is_integer(value) and value in 0..0xFFFFFFFF, do: :ok
  defp validate_checksum(value), do: {:error, {:invalid_field, :file_checksum, value}}

  defp validate_boolean(value, _field) when is_boolean(value), do: :ok
  defp validate_boolean(value, field), do: {:error, {:invalid_field, field, value}}

  defp fixed_width(:adaptive), do: nil
  defp fixed_width(value), do: value

  defp fault(state, condition) do
    case FaultPolicy.handler(state.fault_policy, condition, state.options) do
      :cancel ->
        terminal_fault(state, :transaction_fault, condition)

      :abandon ->
        terminal_fault(state, :abandoned, condition)

      :ignore ->
        indication =
          Indication.new(:fault, state.transaction_id, %{
            condition: condition,
            progress: state.next_offset
          })

        {:ok, Transition.new(state, indications: [indication], timers: [{:start, :check}])}

      :suspend ->
        suspend(state, condition)
    end
  end

  defp terminal_fault(state, type, condition) do
    state = %{state | phase: :faulted}

    indication =
      Indication.new(type, state.transaction_id, %{
        condition: condition,
        progress: state.next_offset
      })

    {:ok, Transition.new(state, indications: [indication])}
  end
end
