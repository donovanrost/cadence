defmodule CCSDS.CFDP.TLV.Codec do
  @moduledoc """
  Strict codec for the standard CFDP type-length-value options.
  """

  alias CCSDS.CFDP
  alias CCSDS.CFDP.Encoding
  alias CCSDS.CFDP.TLV

  alias CCSDS.CFDP.TLV.{
    EntityID,
    FaultHandlerOverride,
    FilestoreRequest,
    FilestoreResponse,
    FlowLabel,
    MessageToUser
  }

  @actions %{
    create_file: 0,
    delete_file: 1,
    rename_file: 2,
    append_file: 3,
    replace_file: 4,
    create_directory: 5,
    remove_directory: 6,
    deny_file: 7,
    deny_directory: 8
  }
  @actions_by_code Map.new(@actions, fn {name, code} -> {code, name} end)
  @two_name_actions [:rename_file, :append_file, :replace_file]

  @handlers %{cancel: 1, suspend: 2, ignore: 3, abandon: 4}
  @handlers_by_code Map.new(@handlers, fn {name, code} -> {code, name} end)

  @spec encode(TLV.t()) :: {:ok, binary()} | {:error, term()}
  def encode(tlv) do
    with {:ok, type, value} <- encode_value(tlv),
         :ok <- validate_value_length(value) do
      {:ok, <<type, byte_size(value), value::binary>>}
    end
  end

  @spec encode_all([TLV.t()]) :: {:ok, binary()} | {:error, term()}
  def encode_all(tlvs) when is_list(tlvs) do
    Enum.reduce_while(tlvs, {:ok, []}, fn tlv, {:ok, encoded} ->
      case encode(tlv) do
        {:ok, value} -> {:cont, {:ok, [value | encoded]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, encoded} -> {:ok, encoded |> Enum.reverse() |> IO.iodata_to_binary()}
      {:error, _reason} = error -> error
    end
  end

  def encode_all(value), do: {:error, {:invalid_tlv_list, value}}

  @spec decode(binary()) :: {:ok, TLV.t(), binary()} | {:error, term()}
  def decode(<<type, length, rest::binary>>) do
    if byte_size(rest) >= length do
      <<value::binary-size(^length), trailing::binary>> = rest

      case decode_value(type, value) do
        {:ok, tlv} -> {:ok, tlv, trailing}
        {:error, _reason} = error -> error
      end
    else
      {:error, {:truncated_tlv, type, length, byte_size(rest)}}
    end
  end

  def decode(binary), do: {:error, {:truncated_tlv_header, byte_size(binary)}}

  @spec decode_all(binary()) :: {:ok, [TLV.t()]} | {:error, term()}
  def decode_all(binary) when is_binary(binary), do: decode_values(binary, [])

  defp decode_values(<<>>, decoded), do: {:ok, Enum.reverse(decoded)}

  defp decode_values(binary, decoded) do
    case decode(binary) do
      {:ok, tlv, rest} -> decode_values(rest, [tlv | decoded])
      {:error, _reason} = error -> error
    end
  end

  defp encode_value(%FilestoreRequest{} = request) do
    with {:ok, action_code} <- action_code(request.action),
         :ok <- validate_second_name(request.action, request.second_file_name),
         {:ok, first} <- Encoding.encode_lv(request.first_file_name, :first_file_name),
         {:ok, second} <- encode_second_name(request.action, request.second_file_name) do
      {:ok, 0, <<action_code::4, 0::4, first::binary, second::binary>>}
    end
  end

  defp encode_value(%FilestoreResponse{} = response) do
    with {:ok, action_code} <- action_code(response.action),
         :ok <- Encoding.validate_range(response.status, 0, 15, :filestore_status),
         :ok <- validate_filestore_status(response.action, response.status),
         :ok <- validate_second_name(response.action, response.second_file_name),
         {:ok, first} <- Encoding.encode_lv(response.first_file_name, :first_file_name),
         {:ok, second} <- encode_second_name(response.action, response.second_file_name),
         {:ok, message} <-
           Encoding.encode_lv(response.filestore_message, :filestore_message) do
      {:ok, 1,
       <<action_code::4, response.status::4, first::binary, second::binary, message::binary>>}
    end
  end

  defp encode_value(%MessageToUser{message: message}) when is_binary(message),
    do: {:ok, 2, message}

  defp encode_value(%FaultHandlerOverride{} = override) do
    with :ok <- validate_fault_condition(override.condition),
         {:ok, handler} <- fetch_code(@handlers, override.handler, :fault_handler) do
      condition = CFDP.condition_code(override.condition)
      {:ok, 4, <<condition::4, handler::4>>}
    end
  end

  defp encode_value(%FlowLabel{value: value}) when is_binary(value), do: {:ok, 5, value}

  defp encode_value(%EntityID{} = entity) do
    with :ok <-
           Encoding.validate_range(entity.entity_id, 0, 0xFFFFFFFFFFFFFFFF, :entity_id),
         octets <- entity.octets || Encoding.minimum_octets(entity.entity_id),
         :ok <- validate_entity_id_octets(octets),
         {:ok, encoded} <- Encoding.encode_uint(entity.entity_id, octets, :entity_id) do
      {:ok, 6, encoded}
    end
  end

  defp encode_value(value), do: {:error, {:unsupported_cfdp_tlv, value}}

  defp decode_value(0, <<action_code::4, spare::4, rest::binary>>) do
    with :ok <- validate_spare(spare, :filestore_request),
         {:ok, action} <- action(action_code),
         {:ok, first, rest} <- Encoding.decode_lv(rest, :first_file_name),
         {:ok, second, rest} <- decode_second_name(action, rest),
         :ok <- Encoding.require_empty(rest, :filestore_request) do
      {:ok,
       %FilestoreRequest{
         action: action,
         first_file_name: first,
         second_file_name: second
       }}
    end
  end

  defp decode_value(0, value), do: {:error, {:malformed_tlv_value, :filestore_request, value}}

  defp decode_value(1, <<action_code::4, status::4, rest::binary>>) do
    with {:ok, action} <- action(action_code),
         :ok <- validate_filestore_status(action, status),
         {:ok, first, rest} <- Encoding.decode_lv(rest, :first_file_name),
         {:ok, second, rest} <- decode_second_name(action, rest),
         {:ok, message, rest} <- Encoding.decode_lv(rest, :filestore_message),
         :ok <- Encoding.require_empty(rest, :filestore_response) do
      {:ok,
       %FilestoreResponse{
         action: action,
         status: status,
         first_file_name: first,
         second_file_name: second,
         filestore_message: message
       }}
    end
  end

  defp decode_value(1, value), do: {:error, {:malformed_tlv_value, :filestore_response, value}}
  defp decode_value(2, value), do: {:ok, %MessageToUser{message: value}}

  defp decode_value(4, <<condition_code::4, handler_code::4>>) do
    with {:ok, condition} <- CFDP.condition(condition_code),
         :ok <- validate_fault_condition(condition),
         {:ok, handler} <- fetch_name(@handlers_by_code, handler_code, :fault_handler) do
      {:ok, %FaultHandlerOverride{condition: condition, handler: handler}}
    end
  end

  defp decode_value(4, value),
    do: {:error, {:malformed_tlv_value, :fault_handler_override, value}}

  defp decode_value(5, value), do: {:ok, %FlowLabel{value: value}}

  defp decode_value(6, value) when byte_size(value) in 1..8 do
    {:ok, %EntityID{entity_id: :binary.decode_unsigned(value), octets: byte_size(value)}}
  end

  defp decode_value(6, value), do: {:error, {:invalid_entity_id_length, byte_size(value)}}
  defp decode_value(type, _value), do: {:error, {:unsupported_cfdp_tlv_type, type}}

  defp action_code(action), do: fetch_code(@actions, action, :filestore_action)
  defp action(code), do: fetch_name(@actions_by_code, code, :filestore_action)

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

  defp validate_second_name(action, value) when action in @two_name_actions do
    if is_binary(value),
      do: :ok,
      else: {:error, {:second_file_name_required, action}}
  end

  defp validate_second_name(_action, nil), do: :ok

  defp validate_second_name(action, value),
    do: {:error, {:unexpected_second_file_name, action, value}}

  defp encode_second_name(action, value) when action in @two_name_actions,
    do: Encoding.encode_lv(value, :second_file_name)

  defp encode_second_name(_action, nil), do: {:ok, <<>>}

  defp decode_second_name(action, binary) when action in @two_name_actions,
    do: Encoding.decode_lv(binary, :second_file_name)

  defp decode_second_name(_action, binary), do: {:ok, nil, binary}

  defp validate_fault_condition(condition)
       when condition in [:no_error, :suspend_request_received, :cancel_request_received],
       do: {:error, {:invalid_field, :fault_condition, condition}}

  defp validate_fault_condition(condition) do
    case CFDP.condition_code(condition) do
      code when code in 1..15 -> :ok
    end
  rescue
    KeyError -> {:error, {:invalid_field, :fault_condition, condition}}
  end

  defp validate_value_length(value) when byte_size(value) <= 0xFF, do: :ok
  defp validate_value_length(value), do: {:error, {:cfdp_tlv_too_large, byte_size(value)}}

  defp validate_spare(0, _context), do: :ok
  defp validate_spare(value, context), do: {:error, {:nonzero_spare_bits, context, value}}

  defp validate_entity_id_octets(value) when value in 1..8, do: :ok
  defp validate_entity_id_octets(value), do: {:error, {:invalid_field, :entity_id_octets, value}}

  defp validate_filestore_status(action, status) do
    valid =
      case action do
        action when action in [:create_file, :create_directory] -> [0, 1, 15]
        action when action in [:delete_file, :remove_directory] -> [0, 1, 2, 15]
        action when action in [:rename_file, :append_file, :replace_file] -> [0, 1, 2, 3, 15]
        action when action in [:deny_file, :deny_directory] -> [0, 2, 15]
      end

    if status in valid,
      do: :ok,
      else: {:error, {:invalid_filestore_status, action, status}}
  end
end
