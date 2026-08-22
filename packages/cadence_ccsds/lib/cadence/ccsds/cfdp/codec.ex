defmodule Cadence.CCSDS.CFDP.Codec do
  @moduledoc """
  Strict CCSDS 727.0-B-5 CFDP PDU codec.

  The codec preserves identifier widths, rejects reserved wire values and
  spare bits, supports both file-size encodings, and validates the optional
  PDU CRC. It does not perform transaction sequencing or filestore I/O.
  """

  alias Cadence.CCSDS.CFDP
  alias Cadence.CCSDS.CFDP.{Configuration, Encoding, FileData, PDU}
  alias Cadence.CCSDS.CFDP.TLV
  alias Cadence.CCSDS.CFDP.TLV.Codec, as: TLVCodec
  alias Cadence.CCSDS.FrameErrorControl

  alias Cadence.CCSDS.CFDP.Directive.{
    Acknowledgement,
    EndOfFile,
    Finished,
    KeepAlive,
    Metadata,
    NegativeAcknowledgement,
    Prompt
  }

  @version 1
  @directive_codes %{
    end_of_file: 0x04,
    finished: 0x05,
    acknowledgement: 0x06,
    metadata: 0x07,
    negative_acknowledgement: 0x08,
    prompt: 0x09,
    keep_alive: 0x0C
  }

  @record_states %{
    no_start_no_end: 0,
    start_no_end: 1,
    no_start_end: 2,
    start_and_end: 3
  }
  @record_states_by_code Map.new(@record_states, fn {name, code} -> {code, name} end)

  @transaction_statuses %{undefined: 0, active: 1, terminated: 2, unrecognized: 3}
  @transaction_statuses_by_code Map.new(@transaction_statuses, fn {name, code} ->
                                  {code, name}
                                end)

  @file_statuses %{
    discarded_deliberately: 0,
    discarded_by_filestore: 1,
    retained: 2,
    unreported: 3
  }
  @file_statuses_by_code Map.new(@file_statuses, fn {name, code} -> {code, name} end)

  @spec encode(PDU.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def encode(pdu, opts \\ [])

  def encode(%PDU{} = pdu, opts) when is_list(opts) do
    with {:ok, configuration} <- configuration(opts),
         {:ok, entity_octets} <- entity_octets(pdu, configuration),
         {:ok, sequence_octets} <- sequence_octets(pdu, configuration),
         :ok <- validate_common(pdu),
         {:ok, pdu_type, segment_metadata?, direction, data} <-
           encode_payload(pdu.payload, pdu, configuration),
         :ok <- validate_direction(pdu.direction, direction),
         :ok <- validate_data_length(data, pdu.crc?, configuration),
         {:ok, header} <-
           encode_header(
             pdu,
             pdu_type,
             segment_metadata?,
             entity_octets,
             sequence_octets,
             byte_size(data)
           ) do
      body = header <> data
      {:ok, if(pdu.crc?, do: FrameErrorControl.append(body), else: body)}
    end
  end

  def encode(value, _opts), do: {:error, {:invalid_cfdp_pdu, value}}

  @spec decode(binary(), keyword()) :: {:ok, PDU.t()} | {:error, term()}
  def decode(binary, opts \\ []) when is_binary(binary) and is_list(opts) do
    case decode_prefix(binary, opts) do
      {:ok, pdu, <<>>} ->
        {:ok, pdu}

      {:ok, _pdu, rest} ->
        {:error, {:trailing_bytes, byte_size(binary) - byte_size(rest), byte_size(binary)}}

      {:incomplete, buffer} ->
        {:error, {:truncated_cfdp_pdu, expected_pdu_octets(buffer), byte_size(buffer)}}

      {:error, _reason} = error ->
        error
    end
  end

  @spec decode_prefix(binary(), keyword()) ::
          {:ok, PDU.t(), binary()} | {:incomplete, binary()} | {:error, term()}
  def decode_prefix(binary, opts \\ []) when is_binary(binary) and is_list(opts) do
    with {:ok, configuration} <- configuration(opts) do
      decode_buffer(binary, configuration)
    end
  end

  @spec pdu_length(binary()) :: {:ok, pos_integer()} | {:error, term()}
  def pdu_length(binary) when byte_size(binary) < 4,
    do: {:error, {:truncated_cfdp_fixed_header, 4, byte_size(binary)}}

  def pdu_length(
        <<_first, data_length::16, _segmentation::1, entity_length_minus_one::3, _metadata::1,
          sequence_length_minus_one::3, _rest::binary>>
      ) do
    entity_octets = entity_length_minus_one + 1
    sequence_octets = sequence_length_minus_one + 1
    {:ok, 4 + entity_octets * 2 + sequence_octets + data_length}
  end

  defp decode_buffer(binary, _configuration) when byte_size(binary) < 4,
    do: {:incomplete, binary}

  defp decode_buffer(
         <<version::3, pdu_type::1, direction_code::1, mode_code::1, crc_code::1, large_code::1,
           data_length::16, segmentation_code::1, entity_length_minus_one::3,
           segment_metadata_code::1, sequence_length_minus_one::3, _rest::binary>> = binary,
         configuration
       ) do
    entity_octets = entity_length_minus_one + 1
    sequence_octets = sequence_length_minus_one + 1
    total_octets = 4 + entity_octets * 2 + sequence_octets + data_length

    with :ok <- validate_version(version),
         :ok <- validate_wire_data_length(data_length, configuration) do
      if byte_size(binary) < total_octets do
        {:incomplete, binary}
      else
        <<pdu_binary::binary-size(^total_octets), rest::binary>> = binary

        wire_header = %{
          pdu_type: pdu_type,
          direction_code: direction_code,
          mode_code: mode_code,
          crc_code: crc_code,
          large_code: large_code,
          segmentation_code: segmentation_code,
          segment_metadata_code: segment_metadata_code,
          entity_octets: entity_octets,
          sequence_octets: sequence_octets,
          data_length: data_length
        }

        decode_complete(pdu_binary, rest, wire_header, configuration)
      end
    end
  end

  defp decode_complete(pdu_binary, trailing, header, configuration) do
    <<_fixed::binary-size(4), variable::binary>> = pdu_binary

    with {:ok, source, variable} <-
           Encoding.decode_uint(variable, header.entity_octets, :source_entity_id),
         {:ok, sequence, variable} <-
           Encoding.decode_uint(
             variable,
             header.sequence_octets,
             :transaction_sequence_number
           ),
         {:ok, destination, data_with_crc} <-
           Encoding.decode_uint(variable, header.entity_octets, :destination_entity_id),
         :ok <- validate_exact_data_length(data_with_crc, header.data_length),
         {:ok, data} <- strip_crc(pdu_binary, data_with_crc, header.crc_code == 1),
         {:ok, transmission_mode} <- transmission_mode(header.mode_code),
         {:ok, direction} <- direction(header.direction_code),
         {:ok, payload, expected_direction} <-
           decode_payload(
             header.pdu_type,
             data,
             header.segment_metadata_code == 1,
             header.large_code == 1,
             transmission_mode,
             configuration
           ),
         :ok <- validate_direction(direction, expected_direction) do
      {:ok,
       %PDU{
         version: @version,
         direction: direction,
         transmission_mode: transmission_mode,
         crc?: header.crc_code == 1,
         large_file?: header.large_code == 1,
         record_boundaries_preserved?: header.segmentation_code == 1,
         source_entity_id: source,
         transaction_sequence_number: sequence,
         destination_entity_id: destination,
         entity_id_octets: header.entity_octets,
         sequence_number_octets: header.sequence_octets,
         payload: payload
       }, trailing}
    end
  end

  defp encode_header(
         pdu,
         pdu_type,
         segment_metadata?,
         entity_octets,
         sequence_octets,
         payload_octets
       ) do
    data_length = payload_octets + if(pdu.crc?, do: 2, else: 0)

    with {:ok, source} <-
           Encoding.encode_uint(pdu.source_entity_id, entity_octets, :source_entity_id),
         {:ok, sequence} <-
           Encoding.encode_uint(
             pdu.transaction_sequence_number,
             sequence_octets,
             :transaction_sequence_number
           ),
         {:ok, destination} <-
           Encoding.encode_uint(
             pdu.destination_entity_id,
             entity_octets,
             :destination_entity_id
           ) do
      {:ok,
       <<@version::3, pdu_type::1, direction_code(pdu.direction)::1,
         transmission_mode_code(pdu.transmission_mode)::1, bool_code(pdu.crc?)::1,
         bool_code(pdu.large_file?)::1, data_length::16,
         bool_code(pdu.record_boundaries_preserved?)::1, entity_octets - 1::3,
         bool_code(segment_metadata?)::1, sequence_octets - 1::3, source::binary,
         sequence::binary, destination::binary>>}
    end
  end

  defp encode_payload(%Metadata{} = metadata, pdu, configuration) do
    file_size_octets = file_size_octets(pdu)

    with :ok <- validate_metadata(metadata, pdu.transmission_mode, configuration),
         {:ok, file_size} <-
           Encoding.encode_uint(metadata.file_size, file_size_octets, :file_size),
         {:ok, source_name} <-
           Encoding.encode_lv(metadata.source_file_name, :source_file_name),
         {:ok, destination_name} <-
           Encoding.encode_lv(metadata.destination_file_name, :destination_file_name),
         {:ok, options} <- TLVCodec.encode_all(metadata.options) do
      directive = @directive_codes.metadata

      {:ok, 0, false, :toward_file_receiver,
       <<directive, 0::1, bool_code(metadata.closure_requested?)::1, 0::2,
         metadata.checksum_type::4, file_size::binary, source_name::binary,
         destination_name::binary, options::binary>>}
    end
  end

  defp encode_payload(%EndOfFile{} = eof, pdu, _configuration) do
    file_size_octets = file_size_octets(pdu)

    with :ok <- validate_eof(eof),
         {:ok, checksum} <- Encoding.encode_uint(eof.file_checksum, 4, :file_checksum),
         {:ok, file_size} <- Encoding.encode_uint(eof.file_size, file_size_octets, :file_size),
         {:ok, fault_location} <- encode_fault_location(eof.condition, eof.fault_location, :eof) do
      directive = @directive_codes.end_of_file
      condition = CFDP.condition_code(eof.condition)

      {:ok, 0, false, :toward_file_receiver,
       <<directive, condition::4, 0::4, checksum::binary, file_size::binary,
         fault_location::binary>>}
    end
  end

  defp encode_payload(%Finished{} = finished, _pdu, _configuration) do
    with :ok <- validate_finished(finished),
         {:ok, responses} <- TLVCodec.encode_all(finished.filestore_responses),
         {:ok, fault_location} <-
           encode_finished_fault_location(finished.condition, finished.fault_location),
         {:ok, file_status} <- fetch_code(@file_statuses, finished.file_status, :file_status) do
      directive = @directive_codes.finished
      condition = CFDP.condition_code(finished.condition)
      delivery = if(finished.delivery_code == :complete, do: 0, else: 1)

      {:ok, 0, false, :toward_file_sender,
       <<directive, condition::4, 0::1, delivery::1, file_status::2, responses::binary,
         fault_location::binary>>}
    end
  end

  defp encode_payload(%Acknowledgement{} = acknowledgement, _pdu, _configuration) do
    with {:ok, directive_code, subtype, direction} <-
           acknowledged_directive(acknowledgement.directive),
         {:ok, transaction_status} <-
           fetch_code(
             @transaction_statuses,
             acknowledgement.transaction_status,
             :transaction_status
           ),
         :ok <- validate_condition(acknowledgement.condition) do
      directive = @directive_codes.acknowledgement
      condition = CFDP.condition_code(acknowledgement.condition)

      {:ok, 0, false, direction,
       <<directive, directive_code::4, subtype::4, condition::4, 0::2, transaction_status::2>>}
    end
  end

  defp encode_payload(%NegativeAcknowledgement{} = nak, pdu, _configuration) do
    file_size_octets = file_size_octets(pdu)

    with :ok <- validate_scope(nak),
         {:ok, start_scope} <-
           Encoding.encode_uint(nak.start_of_scope, file_size_octets, :start_of_scope),
         {:ok, end_scope} <-
           Encoding.encode_uint(nak.end_of_scope, file_size_octets, :end_of_scope),
         {:ok, requests} <- encode_segment_requests(nak.segment_requests, file_size_octets) do
      directive = @directive_codes.negative_acknowledgement

      {:ok, 0, false, :toward_file_sender,
       <<directive, start_scope::binary, end_scope::binary, requests::binary>>}
    end
  end

  defp encode_payload(%Prompt{} = prompt, _pdu, _configuration)
       when prompt.response in [:nak, :keep_alive] do
    directive = @directive_codes.prompt
    response = if(prompt.response == :nak, do: 0, else: 1)
    {:ok, 0, false, :toward_file_receiver, <<directive, response::1, 0::7>>}
  end

  defp encode_payload(%Prompt{} = prompt, _pdu, _configuration),
    do: {:error, {:invalid_field, :prompt_response, prompt.response}}

  defp encode_payload(%KeepAlive{} = keep_alive, pdu, _configuration) do
    with {:ok, progress} <-
           Encoding.encode_uint(keep_alive.progress, file_size_octets(pdu), :progress) do
      directive = @directive_codes.keep_alive
      {:ok, 0, false, :toward_file_sender, <<directive, progress::binary>>}
    end
  end

  defp encode_payload(%FileData{} = file_data, pdu, _configuration) do
    with {:ok, offset} <-
           Encoding.encode_uint(file_data.offset, file_size_octets(pdu), :offset),
         {:ok, segment_metadata?, administration} <- encode_segment_metadata(file_data),
         :ok <- validate_file_data(file_data, pdu, segment_metadata?) do
      {:ok, 1, segment_metadata?, :toward_file_receiver,
       <<administration::binary, offset::binary, file_data.data::binary>>}
    end
  end

  defp encode_payload(value, _pdu, _configuration),
    do: {:error, {:unsupported_cfdp_payload, value}}

  defp decode_payload(0, <<directive, parameters::binary>>, false, large?, mode, configuration) do
    decode_directive(directive, parameters, large?, mode, configuration)
  end

  defp decode_payload(0, _data, true, _large?, _mode, _configuration),
    do: {:error, :segment_metadata_flag_set_for_file_directive}

  defp decode_payload(1, data, segment_metadata?, large?, _mode, _configuration),
    do: decode_file_data(data, segment_metadata?, large?)

  defp decode_payload(type, _data, _segment_metadata?, _large?, _mode, _configuration),
    do: {:error, {:invalid_pdu_type, type}}

  defp decode_directive(0x07, parameters, large?, mode, configuration),
    do: decode_metadata(parameters, large?, mode, configuration)

  defp decode_directive(0x04, parameters, large?, _mode, _configuration),
    do: decode_eof(parameters, large?)

  defp decode_directive(0x05, parameters, _large?, _mode, _configuration),
    do: decode_finished(parameters)

  defp decode_directive(0x06, parameters, _large?, _mode, _configuration),
    do: decode_acknowledgement(parameters)

  defp decode_directive(0x08, parameters, large?, _mode, _configuration),
    do: decode_nak(parameters, large?)

  defp decode_directive(0x09, parameters, _large?, _mode, _configuration),
    do: decode_prompt(parameters)

  defp decode_directive(0x0C, parameters, large?, _mode, _configuration),
    do: decode_keep_alive(parameters, large?)

  defp decode_directive(code, _parameters, _large?, _mode, _configuration),
    do: {:error, {:reserved_file_directive_code, code}}

  defp decode_metadata(
         <<reserved::1, closure_code::1, spare::2, checksum_type::4, rest::binary>>,
         large?,
         mode,
         configuration
       ) do
    file_size_octets = file_size_octets(large?)

    with :ok <- validate_spare(reserved, :metadata_reserved),
         :ok <- validate_spare(spare, :metadata_spare),
         :ok <- validate_closure_code(closure_code, mode),
         :ok <- validate_checksum_type(checksum_type, configuration),
         {:ok, file_size, rest} <- Encoding.decode_uint(rest, file_size_octets, :file_size),
         {:ok, source_name, rest} <- Encoding.decode_lv(rest, :source_file_name),
         {:ok, destination_name, options_binary} <-
           Encoding.decode_lv(rest, :destination_file_name),
         {:ok, options} <- TLVCodec.decode_all(options_binary),
         :ok <- validate_metadata_options(options) do
      {:ok,
       %Metadata{
         closure_requested?: closure_code == 1,
         checksum_type: checksum_type,
         file_size: file_size,
         source_file_name: source_name,
         destination_file_name: destination_name,
         options: options
       }, :toward_file_receiver}
    end
  end

  defp decode_metadata(value, _large?, _mode, _configuration),
    do: {:error, {:malformed_directive, :metadata, value}}

  defp decode_eof(<<condition_code::4, spare::4, rest::binary>>, large?) do
    file_size_octets = file_size_octets(large?)

    with :ok <- validate_spare(spare, :end_of_file),
         {:ok, condition} <- CFDP.condition(condition_code),
         {:ok, checksum, rest} <- Encoding.decode_uint(rest, 4, :file_checksum),
         {:ok, file_size, fault_binary} <-
           Encoding.decode_uint(rest, file_size_octets, :file_size),
         {:ok, fault_location} <- decode_fault_location(condition, fault_binary, :eof) do
      {:ok,
       %EndOfFile{
         condition: condition,
         file_checksum: checksum,
         file_size: file_size,
         fault_location: fault_location
       }, :toward_file_receiver}
    end
  end

  defp decode_eof(value, _large?), do: {:error, {:malformed_directive, :end_of_file, value}}

  defp decode_finished(
         <<condition_code::4, spare::1, delivery_code::1, status_code::2, tlvs_binary::binary>>
       ) do
    with :ok <- validate_spare(spare, :finished),
         {:ok, condition} <- CFDP.condition(condition_code),
         {:ok, file_status} <- fetch_name(@file_statuses_by_code, status_code, :file_status),
         {:ok, tlvs} <- TLVCodec.decode_all(tlvs_binary),
         {:ok, responses, fault_location} <- split_finished_tlvs(tlvs),
         :ok <- validate_finished_fault_location(condition, fault_location) do
      {:ok,
       %Finished{
         condition: condition,
         delivery_code: if(delivery_code == 0, do: :complete, else: :incomplete),
         file_status: file_status,
         filestore_responses: responses,
         fault_location: fault_location
       }, :toward_file_sender}
    end
  end

  defp decode_finished(value), do: {:error, {:malformed_directive, :finished, value}}

  defp decode_acknowledgement(
         <<directive_code::4, subtype::4, condition_code::4, spare::2, status_code::2>>
       ) do
    with :ok <- validate_spare(spare, :acknowledgement),
         {:ok, directive, direction} <- decode_acknowledged_directive(directive_code, subtype),
         {:ok, condition} <- CFDP.condition(condition_code),
         {:ok, status} <-
           fetch_name(@transaction_statuses_by_code, status_code, :transaction_status) do
      {:ok,
       %Acknowledgement{
         directive: directive,
         condition: condition,
         transaction_status: status
       }, direction}
    end
  end

  defp decode_acknowledgement(value),
    do: {:error, {:malformed_directive, :acknowledgement, value}}

  defp decode_nak(parameters, large?) do
    octets = file_size_octets(large?)

    with {:ok, start_scope, rest} <- Encoding.decode_uint(parameters, octets, :start_of_scope),
         {:ok, end_scope, rest} <- Encoding.decode_uint(rest, octets, :end_of_scope),
         {:ok, requests} <- decode_segment_requests(rest, octets),
         nak = %NegativeAcknowledgement{
           start_of_scope: start_scope,
           end_of_scope: end_scope,
           segment_requests: requests
         },
         :ok <- validate_scope(nak) do
      {:ok, nak, :toward_file_sender}
    end
  end

  defp decode_prompt(<<response::1, spare::7>>) do
    with :ok <- validate_spare(spare, :prompt) do
      {:ok, %Prompt{response: if(response == 0, do: :nak, else: :keep_alive)},
       :toward_file_receiver}
    end
  end

  defp decode_prompt(value), do: {:error, {:malformed_directive, :prompt, value}}

  defp decode_keep_alive(parameters, large?) do
    with {:ok, progress, rest} <-
           Encoding.decode_uint(parameters, file_size_octets(large?), :progress),
         :ok <- Encoding.require_empty(rest, :keep_alive) do
      {:ok, %KeepAlive{progress: progress}, :toward_file_sender}
    end
  end

  defp decode_file_data(data, segment_metadata?, large?) do
    with {:ok, record_state, metadata, rest} <-
           decode_segment_metadata(data, segment_metadata?),
         {:ok, offset, file_data} <- Encoding.decode_uint(rest, file_size_octets(large?), :offset) do
      {:ok,
       %FileData{
         offset: offset,
         data: file_data,
         record_continuation_state: record_state,
         segment_metadata: metadata
       }, :toward_file_receiver}
    end
  end

  defp encode_segment_metadata(%FileData{segment_metadata: nil}) do
    if Map.has_key?(@record_states, :no_start_no_end),
      do: {:ok, false, <<>>},
      else: {:error, :invalid_record_state_table}
  end

  defp encode_segment_metadata(%FileData{} = file_data)
       when is_binary(file_data.segment_metadata) and byte_size(file_data.segment_metadata) <= 63 do
    with {:ok, record_state} <-
           fetch_code(
             @record_states,
             file_data.record_continuation_state,
             :record_continuation_state
           ) do
      {:ok, true,
       <<record_state::2, byte_size(file_data.segment_metadata)::6,
         file_data.segment_metadata::binary>>}
    end
  end

  defp encode_segment_metadata(%FileData{} = file_data) do
    {:error, {:invalid_field, :segment_metadata, file_data.segment_metadata}}
  end

  defp decode_segment_metadata(data, false),
    do: {:ok, :no_start_no_end, nil, data}

  defp decode_segment_metadata(<<state_code::2, metadata_length::6, rest::binary>>, true) do
    if byte_size(rest) >= metadata_length do
      <<metadata::binary-size(^metadata_length), trailing::binary>> = rest

      with {:ok, state} <-
             fetch_name(@record_states_by_code, state_code, :record_continuation_state) do
        {:ok, state, metadata, trailing}
      end
    else
      {:error, {:truncated_segment_metadata, metadata_length, byte_size(rest)}}
    end
  end

  defp decode_segment_metadata(value, true),
    do: {:error, {:truncated_segment_metadata_header, byte_size(value)}}

  defp validate_file_data(file_data, pdu, segment_metadata?) do
    cond do
      not is_binary(file_data.data) ->
        {:error, {:invalid_field, :file_data, file_data.data}}

      not segment_metadata? and file_data.record_continuation_state != :no_start_no_end ->
        {:error, :record_continuation_state_requires_segment_metadata}

      pdu.record_boundaries_preserved? and not segment_metadata? ->
        {:error, :record_boundaries_require_segment_metadata}

      true ->
        :ok
    end
  end

  defp validate_metadata(metadata, transmission_mode, configuration) do
    with :ok <- validate_boolean(metadata.closure_requested?, :closure_requested?),
         :ok <- validate_closure(metadata.closure_requested?, transmission_mode),
         :ok <- validate_checksum_type(metadata.checksum_type, configuration) do
      validate_metadata_options(metadata.options)
    end
  end

  defp validate_metadata_options(options) when is_list(options) do
    if Enum.all?(options, fn option ->
         match?(%TLV.FilestoreRequest{}, option) or match?(%TLV.MessageToUser{}, option) or
           match?(%TLV.FaultHandlerOverride{}, option) or match?(%TLV.FlowLabel{}, option)
       end) do
      :ok
    else
      {:error, {:invalid_metadata_options, options}}
    end
  end

  defp validate_metadata_options(value), do: {:error, {:invalid_metadata_options, value}}

  defp validate_checksum_type(type, configuration) do
    if type in configuration.valid_checksum_types,
      do: :ok,
      else: {:error, {:unsupported_checksum_type, type}}
  end

  defp validate_closure(false, _mode), do: :ok
  defp validate_closure(true, :unacknowledged), do: :ok

  defp validate_closure(true, :acknowledged),
    do: {:error, :closure_flag_must_be_zero_in_acknowledged_mode}

  defp validate_closure_code(0, _mode), do: :ok
  defp validate_closure_code(1, :unacknowledged), do: :ok

  defp validate_closure_code(1, :acknowledged),
    do: {:error, :closure_flag_set_in_acknowledged_mode}

  defp validate_eof(eof) do
    with :ok <- validate_condition(eof.condition),
         :ok <- Encoding.validate_range(eof.file_checksum, 0, 0xFFFFFFFF, :file_checksum) do
      validate_fault_location(eof.condition, eof.fault_location, :eof)
    end
  end

  defp validate_finished(finished) do
    with :ok <- validate_condition(finished.condition),
         true <- finished.delivery_code in [:complete, :incomplete],
         true <- Map.has_key?(@file_statuses, finished.file_status),
         true <- is_list(finished.filestore_responses),
         true <- Enum.all?(finished.filestore_responses, &match?(%TLV.FilestoreResponse{}, &1)) do
      validate_finished_fault_location(finished.condition, finished.fault_location)
    else
      false -> {:error, {:invalid_finished_directive, finished}}
      {:error, _reason} = error -> error
    end
  end

  defp validate_condition(condition) do
    CFDP.condition_code(condition)
    :ok
  rescue
    KeyError -> {:error, {:invalid_field, :condition, condition}}
  end

  defp validate_fault_location(:no_error, nil, _context), do: :ok

  defp validate_fault_location(:no_error, value, context),
    do: {:error, {:unexpected_fault_location, context, value}}

  defp validate_fault_location(_condition, %TLV.EntityID{}, _context), do: :ok

  defp validate_fault_location(condition, nil, context),
    do: {:error, {:fault_location_required, context, condition}}

  defp validate_fault_location(_condition, value, context),
    do: {:error, {:invalid_fault_location, context, value}}

  defp validate_finished_fault_location(condition, value)
       when condition in [:no_error, :unsupported_checksum_type] do
    if is_nil(value),
      do: :ok,
      else: {:error, {:unexpected_fault_location, :finished, value}}
  end

  defp validate_finished_fault_location(condition, value),
    do: validate_fault_location(condition, value, :finished)

  defp encode_fault_location(condition, value, context) do
    with :ok <- validate_fault_location(condition, value, context) do
      if is_nil(value), do: {:ok, <<>>}, else: TLVCodec.encode(value)
    end
  end

  defp encode_finished_fault_location(condition, value) do
    with :ok <- validate_finished_fault_location(condition, value) do
      if is_nil(value), do: {:ok, <<>>}, else: TLVCodec.encode(value)
    end
  end

  defp decode_fault_location(:no_error, <<>>, _context), do: {:ok, nil}

  defp decode_fault_location(:no_error, value, context),
    do: {:error, {:unexpected_fault_location, context, value}}

  defp decode_fault_location(condition, binary, context) do
    with {:ok, %TLV.EntityID{} = location, rest} <- TLVCodec.decode(binary),
         :ok <- Encoding.require_empty(rest, context),
         :ok <- validate_fault_location(condition, location, context) do
      {:ok, location}
    else
      {:ok, value, _rest} -> {:error, {:invalid_fault_location, context, value}}
      {:error, _reason} = error -> error
    end
  end

  defp split_finished_tlvs(tlvs) do
    case Enum.split_while(tlvs, &match?(%TLV.FilestoreResponse{}, &1)) do
      {responses, []} ->
        {:ok, responses, nil}

      {responses, [%TLV.EntityID{} = location]} ->
        {:ok, responses, location}

      {_responses, remaining} ->
        {:error, {:invalid_finished_tlvs, remaining}}
    end
  end

  defp encode_segment_requests(requests, octets) when is_list(requests) do
    Enum.reduce_while(requests, {:ok, []}, fn
      {start_offset, end_offset}, {:ok, encoded} ->
        with :ok <- validate_segment_request(start_offset, end_offset),
             {:ok, start_value} <-
               Encoding.encode_uint(start_offset, octets, :segment_request_start),
             {:ok, end_value} <- Encoding.encode_uint(end_offset, octets, :segment_request_end) do
          {:cont, {:ok, [<<start_value::binary, end_value::binary>> | encoded]}}
        else
          {:error, _reason} = error -> {:halt, error}
        end

      value, _acc ->
        {:halt, {:error, {:invalid_segment_request, value}}}
    end)
    |> case do
      {:ok, encoded} -> {:ok, encoded |> Enum.reverse() |> IO.iodata_to_binary()}
      {:error, _reason} = error -> error
    end
  end

  defp encode_segment_requests(value, _octets),
    do: {:error, {:invalid_segment_requests, value}}

  defp decode_segment_requests(<<>>, _octets), do: {:ok, []}

  defp decode_segment_requests(binary, octets) do
    request_octets = octets * 2

    if rem(byte_size(binary), request_octets) == 0 do
      decode_segment_request_values(binary, octets, [])
    else
      {:error, {:malformed_segment_requests, byte_size(binary), request_octets}}
    end
  end

  defp decode_segment_request_values(<<>>, _octets, requests),
    do: {:ok, Enum.reverse(requests)}

  defp decode_segment_request_values(binary, octets, requests) do
    with {:ok, start_offset, rest} <-
           Encoding.decode_uint(binary, octets, :segment_request_start),
         {:ok, end_offset, rest} <- Encoding.decode_uint(rest, octets, :segment_request_end),
         :ok <- validate_segment_request(start_offset, end_offset) do
      decode_segment_request_values(rest, octets, [{start_offset, end_offset} | requests])
    end
  end

  defp validate_scope(%NegativeAcknowledgement{} = nak) do
    with :ok <- validate_nonnegative_scope(nak.start_of_scope, :start_of_scope),
         :ok <- validate_scope_end(nak.start_of_scope, nak.end_of_scope) do
      validate_segment_requests(nak.segment_requests)
    end
  end

  defp validate_nonnegative_scope(value, _field) when is_integer(value) and value >= 0, do: :ok

  defp validate_nonnegative_scope(value, field),
    do: {:error, {:invalid_field, field, value}}

  defp validate_scope_end(start_of_scope, end_of_scope)
       when is_integer(end_of_scope) and end_of_scope >= start_of_scope,
       do: :ok

  defp validate_scope_end(start_of_scope, end_of_scope),
    do: {:error, {:invalid_nak_scope, start_of_scope, end_of_scope}}

  defp validate_segment_requests(requests) when is_list(requests) do
    requests
    |> Enum.map(&validate_segment_request_value/1)
    |> Enum.find(:ok, &match?({:error, _reason}, &1))
  end

  defp validate_segment_requests(value), do: {:error, {:invalid_segment_requests, value}}

  defp validate_segment_request_value({start_offset, end_offset}),
    do: validate_segment_request(start_offset, end_offset)

  defp validate_segment_request_value(value), do: {:error, {:invalid_segment_request, value}}

  defp validate_segment_request(0, 0), do: :ok

  defp validate_segment_request(start_offset, end_offset)
       when is_integer(start_offset) and start_offset >= 0 and is_integer(end_offset) and
              end_offset > start_offset,
       do: :ok

  defp validate_segment_request(start_offset, end_offset),
    do: {:error, {:invalid_segment_request_range, start_offset, end_offset}}

  defp acknowledged_directive(:end_of_file),
    do: {:ok, @directive_codes.end_of_file, 0, :toward_file_sender}

  defp acknowledged_directive(:finished),
    do: {:ok, @directive_codes.finished, 1, :toward_file_receiver}

  defp acknowledged_directive(value),
    do: {:error, {:invalid_field, :acknowledged_directive, value}}

  defp decode_acknowledged_directive(0x04, 0),
    do: {:ok, :end_of_file, :toward_file_sender}

  defp decode_acknowledged_directive(0x05, 1),
    do: {:ok, :finished, :toward_file_receiver}

  defp decode_acknowledged_directive(directive, subtype),
    do: {:error, {:invalid_acknowledged_directive, directive, subtype}}

  defp strip_crc(_pdu_binary, data, false), do: {:ok, data}

  defp strip_crc(_pdu_binary, data, true) when byte_size(data) < 2,
    do: {:error, {:cfdp_crc_missing, byte_size(data)}}

  defp strip_crc(pdu_binary, data, true) do
    case FrameErrorControl.validate_and_strip(pdu_binary) do
      {:ok, _without_crc, _crc} ->
        {:ok, binary_part(data, 0, byte_size(data) - 2)}

      {:error, {:invalid_fecf, expected, received}} ->
        {:error, {:invalid_cfdp_crc, expected, received}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp entity_octets(pdu, configuration) do
    value = pdu.entity_id_octets || configuration.entity_id_octets

    case value do
      :adaptive ->
        with :ok <- validate_identifier(pdu.source_entity_id, :source_entity_id),
             :ok <- validate_identifier(pdu.destination_entity_id, :destination_entity_id) do
          octets =
            max(
              Encoding.minimum_octets(pdu.source_entity_id),
              Encoding.minimum_octets(pdu.destination_entity_id)
            )

          validate_selected_width(octets, :entity_id_octets)
        end

      octets ->
        validate_selected_width(octets, :entity_id_octets)
    end
  end

  defp sequence_octets(pdu, configuration) do
    value = pdu.sequence_number_octets || configuration.sequence_number_octets

    case value do
      :adaptive ->
        with :ok <-
               validate_identifier(
                 pdu.transaction_sequence_number,
                 :transaction_sequence_number
               ) do
          pdu.transaction_sequence_number
          |> Encoding.minimum_octets()
          |> validate_selected_width(:sequence_number_octets)
        end

      octets ->
        validate_selected_width(octets, :sequence_number_octets)
    end
  end

  defp validate_selected_width(value, _field) when value in 1..8, do: {:ok, value}
  defp validate_selected_width(value, field), do: {:error, {:invalid_field, field, value}}

  defp validate_common(pdu) do
    with :ok <- validate_version(pdu.version),
         :ok <- validate_boolean(pdu.crc?, :crc?),
         :ok <- validate_boolean(pdu.large_file?, :large_file?),
         :ok <-
           validate_boolean(
             pdu.record_boundaries_preserved?,
             :record_boundaries_preserved?
           ),
         true <- pdu.direction in [:toward_file_receiver, :toward_file_sender],
         true <- pdu.transmission_mode in [:acknowledged, :unacknowledged],
         :ok <- validate_identifier(pdu.source_entity_id, :source_entity_id),
         :ok <-
           validate_identifier(
             pdu.transaction_sequence_number,
             :transaction_sequence_number
           ),
         :ok <- validate_identifier(pdu.destination_entity_id, :destination_entity_id) do
      :ok
    else
      false -> {:error, {:invalid_cfdp_header, pdu}}
      {:error, _reason} = error -> error
    end
  end

  defp validate_identifier(value, _field)
       when is_integer(value) and value >= 0 and value <= 0xFFFFFFFFFFFFFFFF,
       do: :ok

  defp validate_identifier(value, field), do: {:error, {:invalid_field, field, value}}

  defp validate_version(@version), do: :ok
  defp validate_version(value), do: {:error, {:unsupported_cfdp_version, value}}

  defp validate_boolean(value, _field) when is_boolean(value), do: :ok
  defp validate_boolean(value, field), do: {:error, {:invalid_field, field, value}}

  defp validate_direction(direction, direction), do: :ok

  defp validate_direction(received, expected),
    do: {:error, {:invalid_pdu_direction, expected, received}}

  defp validate_data_length(data, crc?, configuration) do
    length = byte_size(data) + if(crc?, do: 2, else: 0)
    validate_wire_data_length(length, configuration)
  end

  defp validate_exact_data_length(data, expected) when byte_size(data) == expected, do: :ok

  defp validate_exact_data_length(data, expected),
    do: {:error, {:invalid_cfdp_data_length, expected, byte_size(data)}}

  defp validate_wire_data_length(length, configuration)
       when length <= configuration.maximum_pdu_data_octets,
       do: :ok

  defp validate_wire_data_length(length, configuration),
    do:
      {:error, {:pdu_data_exceeds_managed_maximum, length, configuration.maximum_pdu_data_octets}}

  defp configuration(opts) do
    case Keyword.get(opts, :configuration) do
      nil ->
        Configuration.new()

      %Configuration{} = configuration ->
        case Configuration.validate(configuration) do
          :ok -> {:ok, configuration}
          {:error, _reason} = error -> error
        end

      value ->
        {:error, {:invalid_cfdp_configuration, value}}
    end
  end

  defp file_size_octets(%PDU{large_file?: large?}), do: file_size_octets(large?)
  defp file_size_octets(true), do: 8
  defp file_size_octets(false), do: 4

  defp expected_pdu_octets(buffer) do
    case pdu_length(buffer) do
      {:ok, value} -> value
      {:error, _reason} -> 4
    end
  end

  defp transmission_mode(0), do: {:ok, :acknowledged}
  defp transmission_mode(1), do: {:ok, :unacknowledged}
  defp transmission_mode_code(:acknowledged), do: 0
  defp transmission_mode_code(:unacknowledged), do: 1

  defp direction(0), do: {:ok, :toward_file_receiver}
  defp direction(1), do: {:ok, :toward_file_sender}
  defp direction_code(:toward_file_receiver), do: 0
  defp direction_code(:toward_file_sender), do: 1

  defp bool_code(true), do: 1
  defp bool_code(false), do: 0

  defp fetch_code(map, name, field) do
    case Map.fetch(map, name) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, {:invalid_field, field, name}}
    end
  end

  defp fetch_name(map, code, field) do
    case Map.fetch(map, code) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, {:reserved_field_value, field, code}}
    end
  end

  defp validate_spare(0, _context), do: :ok
  defp validate_spare(value, context), do: {:error, {:nonzero_spare_bits, context, value}}
end
