defmodule CCSDS.CFDP.UserOperation.Codec do
  @moduledoc """
  Strict codec for standard proxy and directory Reserved CFDP Messages.

  Encoded values are returned as ordinary Message-to-User TLVs so they can be
  placed directly in Metadata options. Decoding distinguishes reserved CFDP
  messages from application-defined Message-to-User values.
  """

  alias CCSDS.CFDP
  alias CCSDS.CFDP.{Encoding, TransactionID, UserOperation}
  alias CCSDS.CFDP.TLV
  alias CCSDS.CFDP.TLV.Codec, as: TLVCodec

  alias CCSDS.CFDP.UserOperation.{
    DirectoryListingRequest,
    DirectoryListingResponse,
    OriginatingTransactionID,
    ProxyClosureRequest,
    ProxyFaultHandlerOverride,
    ProxyFilestoreRequest,
    ProxyFilestoreResponse,
    ProxyFlowLabel,
    ProxyMessageToUser,
    ProxyPutCancel,
    ProxyPutRequest,
    ProxyPutResponse,
    ProxySegmentationControl,
    ProxyTransmissionMode
  }

  @identifier "cfdp"

  @file_statuses %{
    discarded_deliberately: 0,
    discarded_by_filestore: 1,
    retained: 2,
    unreported: 3
  }
  @file_statuses_by_code Map.new(@file_statuses, fn {name, code} -> {code, name} end)

  @spec encode(UserOperation.t()) :: {:ok, TLV.MessageToUser.t()} | {:error, term()}
  def encode(operation) do
    with {:ok, type, content} <- encode_content(operation) do
      message = <<@identifier, type, content::binary>>
      tlv = %TLV.MessageToUser{message: message}

      case TLVCodec.encode(tlv) do
        {:ok, _encoded} -> {:ok, tlv}
        {:error, _reason} = error -> error
      end
    end
  end

  @spec decode(TLV.MessageToUser.t() | binary()) ::
          {:ok, UserOperation.t()} | {:error, term()}
  def decode(%TLV.MessageToUser{message: message}), do: decode(message)

  def decode(<<@identifier, type, content::binary>>), do: decode_content(type, content)
  def decode(message) when is_binary(message), do: {:error, :not_reserved_cfdp_message}
  def decode(value), do: {:error, {:invalid_message_to_user, value}}

  defp encode_content(%ProxyPutRequest{} = request) do
    with {:ok, entity_id} <-
           encode_identifier_lv(
             request.destination_entity_id,
             request.destination_entity_id_octets,
             :destination_entity_id
           ),
         {:ok, source} <- Encoding.encode_lv(request.source_file_name, :source_file_name),
         {:ok, destination} <-
           Encoding.encode_lv(request.destination_file_name, :destination_file_name) do
      {:ok, 0x00, entity_id <> source <> destination}
    end
  end

  defp encode_content(%ProxyMessageToUser{} = message) do
    with {:ok, encoded} <- Encoding.encode_lv(message.message, :message) do
      {:ok, 0x01, encoded}
    end
  end

  defp encode_content(%ProxyFilestoreRequest{request: request}) do
    with {:ok, value} <- embedded_tlv_value(request, 0) do
      {:ok, 0x02, <<byte_size(value), value::binary>>}
    end
  end

  defp encode_content(%ProxyFaultHandlerOverride{override: override}) do
    with {:ok, value} <- embedded_tlv_value(override, 4) do
      {:ok, 0x03, value}
    end
  end

  defp encode_content(%ProxyTransmissionMode{transmission_mode: mode})
       when mode in [:acknowledged, :unacknowledged] do
    bit = if(mode == :acknowledged, do: 0, else: 1)
    {:ok, 0x04, <<0::7, bit::1>>}
  end

  defp encode_content(%ProxyFlowLabel{value: value}) do
    with {:ok, encoded} <- Encoding.encode_lv(value, :flow_label) do
      {:ok, 0x05, encoded}
    end
  end

  defp encode_content(%ProxySegmentationControl{record_boundaries_preserved?: value})
       when is_boolean(value) do
    bit = if(value, do: 0, else: 1)
    {:ok, 0x06, <<0::7, bit::1>>}
  end

  defp encode_content(%ProxyPutResponse{} = response) do
    with {:ok, condition} <- condition_code(response.condition),
         {:ok, delivery} <- delivery_code(response.delivery_code),
         {:ok, file_status} <- fetch(@file_statuses, response.file_status, :file_status) do
      {:ok, 0x07, <<condition::4, 0::1, delivery::1, file_status::2>>}
    end
  end

  defp encode_content(%ProxyFilestoreResponse{response: response}) do
    with {:ok, value} <- embedded_tlv_value(response, 1) do
      {:ok, 0x08, <<byte_size(value), value::binary>>}
    end
  end

  defp encode_content(%ProxyPutCancel{}), do: {:ok, 0x09, <<>>}

  defp encode_content(%OriginatingTransactionID{} = originating) do
    transaction_id = originating.transaction_id

    with %TransactionID{} <- transaction_id,
         {:ok, entity_octets} <-
           identifier_octets(
             transaction_id.source_entity_id,
             originating.entity_id_octets,
             :source_entity_id
           ),
         {:ok, sequence_octets} <-
           identifier_octets(
             transaction_id.sequence_number,
             originating.sequence_number_octets,
             :transaction_sequence_number
           ),
         {:ok, entity_id} <-
           Encoding.encode_uint(
             transaction_id.source_entity_id,
             entity_octets,
             :source_entity_id
           ),
         {:ok, sequence_number} <-
           Encoding.encode_uint(
             transaction_id.sequence_number,
             sequence_octets,
             :transaction_sequence_number
           ) do
      header = <<0::1, entity_octets - 1::3, 0::1, sequence_octets - 1::3>>
      {:ok, 0x0A, header <> entity_id <> sequence_number}
    else
      value -> {:error, {:invalid_originating_transaction_id, value}}
    end
  end

  defp encode_content(%ProxyClosureRequest{closure_requested?: value}) when is_boolean(value) do
    bit = if(value, do: 1, else: 0)
    {:ok, 0x0B, <<0::7, bit::1>>}
  end

  defp encode_content(%DirectoryListingRequest{} = request) do
    with {:ok, directory} <- Encoding.encode_lv(request.directory_name, :directory_name),
         {:ok, file} <-
           Encoding.encode_lv(request.directory_file_name, :directory_file_name) do
      {:ok, 0x10, directory <> file}
    end
  end

  defp encode_content(%DirectoryListingResponse{} = response) do
    with {:ok, response_code} <- listing_response_code(response.listing_response),
         {:ok, directory} <- Encoding.encode_lv(response.directory_name, :directory_name),
         {:ok, file} <-
           Encoding.encode_lv(response.directory_file_name, :directory_file_name) do
      {:ok, 0x11, <<response_code::1, 0::7, directory::binary, file::binary>>}
    end
  end

  defp encode_content(value), do: {:error, {:unsupported_cfdp_user_operation, value}}

  defp decode_content(0x00, content) do
    with {:ok, destination_entity_id, entity_octets, rest} <-
           decode_identifier_lv(content, :destination_entity_id),
         {:ok, source_file_name, rest} <- Encoding.decode_lv(rest, :source_file_name),
         {:ok, destination_file_name, rest} <-
           Encoding.decode_lv(rest, :destination_file_name),
         :ok <- Encoding.require_empty(rest, :proxy_put_request) do
      {:ok,
       %ProxyPutRequest{
         destination_entity_id: destination_entity_id,
         destination_entity_id_octets: entity_octets,
         source_file_name: source_file_name,
         destination_file_name: destination_file_name
       }}
    end
  end

  defp decode_content(0x01, content) do
    with {:ok, message, rest} <- Encoding.decode_lv(content, :message),
         :ok <- Encoding.require_empty(rest, :proxy_message_to_user) do
      {:ok, %ProxyMessageToUser{message: message}}
    end
  end

  defp decode_content(0x02, content) do
    with {:ok, request} <- decode_length_prefixed_tlv(content, 0, :proxy_filestore_request) do
      {:ok, %ProxyFilestoreRequest{request: request}}
    end
  end

  defp decode_content(0x03, content) do
    with {:ok, override} <- decode_exact_tlv_value(content, 4, :proxy_fault_handler_override) do
      {:ok, %ProxyFaultHandlerOverride{override: override}}
    end
  end

  defp decode_content(0x04, <<0::7, mode::1>>),
    do: {:ok, %ProxyTransmissionMode{transmission_mode: transmission_mode(mode)}}

  defp decode_content(0x04, content), do: malformed(:proxy_transmission_mode, content)

  defp decode_content(0x05, content) do
    with {:ok, value, rest} <- Encoding.decode_lv(content, :flow_label),
         :ok <- Encoding.require_empty(rest, :proxy_flow_label) do
      {:ok, %ProxyFlowLabel{value: value}}
    end
  end

  defp decode_content(0x06, <<0::7, control::1>>),
    do: {:ok, %ProxySegmentationControl{record_boundaries_preserved?: control == 0}}

  defp decode_content(0x06, content), do: malformed(:proxy_segmentation_control, content)

  defp decode_content(
         0x07,
         <<condition_code::4, 0::1, delivery_code::1, file_status_code::2>>
       ) do
    with {:ok, condition} <- CFDP.condition(condition_code),
         {:ok, file_status} <-
           fetch(@file_statuses_by_code, file_status_code, :file_status) do
      {:ok,
       %ProxyPutResponse{
         condition: condition,
         delivery_code: if(delivery_code == 0, do: :complete, else: :incomplete),
         file_status: file_status
       }}
    end
  end

  defp decode_content(0x07, content), do: malformed(:proxy_put_response, content)

  defp decode_content(0x08, content) do
    with {:ok, response} <- decode_length_prefixed_tlv(content, 1, :proxy_filestore_response) do
      {:ok, %ProxyFilestoreResponse{response: response}}
    end
  end

  defp decode_content(0x09, <<>>), do: {:ok, %ProxyPutCancel{}}
  defp decode_content(0x09, content), do: malformed(:proxy_put_cancel, content)

  defp decode_content(
         0x0A,
         <<0::1, entity_length::3, 0::1, sequence_length::3, rest::binary>>
       ) do
    entity_octets = entity_length + 1
    sequence_octets = sequence_length + 1

    with {:ok, source_entity_id, rest} <-
           Encoding.decode_uint(rest, entity_octets, :source_entity_id),
         {:ok, sequence_number, rest} <-
           Encoding.decode_uint(rest, sequence_octets, :transaction_sequence_number),
         :ok <- Encoding.require_empty(rest, :originating_transaction_id) do
      {:ok,
       %OriginatingTransactionID{
         transaction_id: TransactionID.new(source_entity_id, sequence_number),
         entity_id_octets: entity_octets,
         sequence_number_octets: sequence_octets
       }}
    end
  end

  defp decode_content(0x0A, content), do: malformed(:originating_transaction_id, content)

  defp decode_content(0x0B, <<0::7, closure::1>>),
    do: {:ok, %ProxyClosureRequest{closure_requested?: closure == 1}}

  defp decode_content(0x0B, content), do: malformed(:proxy_closure_request, content)

  defp decode_content(0x10, content) do
    with {:ok, directory_name, rest} <- Encoding.decode_lv(content, :directory_name),
         {:ok, directory_file_name, rest} <-
           Encoding.decode_lv(rest, :directory_file_name),
         :ok <- Encoding.require_empty(rest, :directory_listing_request) do
      {:ok,
       %DirectoryListingRequest{
         directory_name: directory_name,
         directory_file_name: directory_file_name
       }}
    end
  end

  defp decode_content(0x11, <<response::1, 0::7, rest::binary>>) do
    with {:ok, directory_name, rest} <- Encoding.decode_lv(rest, :directory_name),
         {:ok, directory_file_name, rest} <-
           Encoding.decode_lv(rest, :directory_file_name),
         :ok <- Encoding.require_empty(rest, :directory_listing_response) do
      {:ok,
       %DirectoryListingResponse{
         listing_response: listing_response(response),
         directory_name: directory_name,
         directory_file_name: directory_file_name
       }}
    end
  end

  defp decode_content(0x11, content), do: malformed(:directory_listing_response, content)

  defp decode_content(type, _content),
    do: {:error, {:unsupported_reserved_cfdp_message_type, type}}

  defp encode_identifier_lv(value, requested_octets, field) do
    with {:ok, octets} <- identifier_octets(value, requested_octets, field),
         {:ok, encoded} <- Encoding.encode_uint(value, octets, field) do
      Encoding.encode_lv(encoded, field)
    end
  end

  defp identifier_octets(value, nil, field) do
    with :ok <- Encoding.validate_range(value, 0, 0xFFFFFFFFFFFFFFFF, field) do
      {:ok, Encoding.minimum_octets(value)}
    end
  end

  defp identifier_octets(value, octets, field) when octets in 1..8 do
    with {:ok, _encoded} <- Encoding.encode_uint(value, octets, field), do: {:ok, octets}
  end

  defp identifier_octets(_value, octets, field),
    do: {:error, {:invalid_identifier_width, field, octets}}

  defp decode_identifier_lv(content, field) do
    with {:ok, encoded, rest} <- Encoding.decode_lv(content, field),
         :ok <- validate_identifier_length(encoded, field) do
      {:ok, :binary.decode_unsigned(encoded), byte_size(encoded), rest}
    end
  end

  defp validate_identifier_length(value, _field) when byte_size(value) in 1..8, do: :ok

  defp validate_identifier_length(value, field),
    do: {:error, {:invalid_identifier_length, field, byte_size(value)}}

  defp embedded_tlv_value(tlv, expected_type) do
    case TLVCodec.encode(tlv) do
      {:ok, <<^expected_type, length, value::binary-size(length)>>} -> {:ok, value}
      {:ok, _encoded} -> {:error, {:unexpected_embedded_tlv, expected_type, tlv}}
      {:error, _reason} = error -> error
    end
  end

  defp decode_length_prefixed_tlv(<<length, rest::binary>>, type, context)
       when byte_size(rest) >= length do
    <<value::binary-size(^length), trailing::binary>> = rest

    with :ok <- Encoding.require_empty(trailing, context),
         {:ok, tlv, <<>>} <- TLVCodec.decode(<<type, length, value::binary>>) do
      {:ok, tlv}
    end
  end

  defp decode_length_prefixed_tlv(content, _type, context), do: malformed(context, content)

  defp decode_exact_tlv_value(content, type, _context) when byte_size(content) <= 0xFF do
    case TLVCodec.decode(<<type, byte_size(content), content::binary>>) do
      {:ok, tlv, <<>>} -> {:ok, tlv}
      {:error, _reason} = error -> error
    end
  end

  defp condition_code(condition) do
    {:ok, CFDP.condition_code(condition)}
  rescue
    KeyError -> {:error, {:invalid_field, :condition, condition}}
  end

  defp delivery_code(:complete), do: {:ok, 0}
  defp delivery_code(:incomplete), do: {:ok, 1}
  defp delivery_code(value), do: {:error, {:invalid_field, :delivery_code, value}}

  defp listing_response_code(:successful), do: {:ok, 0}
  defp listing_response_code(:unsuccessful), do: {:ok, 1}

  defp listing_response_code(value),
    do: {:error, {:invalid_field, :listing_response, value}}

  defp listing_response(0), do: :successful
  defp listing_response(1), do: :unsuccessful
  defp transmission_mode(0), do: :acknowledged
  defp transmission_mode(1), do: :unacknowledged

  defp fetch(map, key, field) do
    case Map.fetch(map, key) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, {:invalid_field, field, key}}
    end
  end

  defp malformed(context, content), do: {:error, {:malformed_user_operation, context, content}}
end
