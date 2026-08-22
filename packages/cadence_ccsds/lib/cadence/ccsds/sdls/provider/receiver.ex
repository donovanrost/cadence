defmodule Cadence.CCSDS.SDLS.Provider.Receiver do
  @moduledoc false

  import Bitwise

  alias Cadence.CCSDS.SDLS.{
    AntiReplay,
    AuthenticationMask,
    Channel,
    Operation,
    ProcessResult,
    SecurityAssociation,
    SecurityHeader,
    Service,
    Verification
  }

  def process(request, state) do
    with :ok <- validate_request(request),
         {:ok, key, association, spi} <- fetch_association(request, state),
         :ok <- validate_service(request, association, spi),
         {:ok, header, protected_and_mac, encoded_header} <-
           decode_header(request.secured_payload, association, spi),
         {:ok, protected_data, mac} <- split_trailer(protected_and_mac, association, spi),
         operation <- operation(request, association, header, encoded_header),
         {:ok, crypto_state} <-
           verify_mac(
             request.frame_prefix,
             encoded_header,
             protected_data,
             mac,
             operation,
             state
           ),
         dynamic <- Map.fetch!(state.receiver_state, key),
         {:ok, received_sequence} <- verify_replay(header, association, dynamic, spi),
         {:ok, clear_with_padding, next_iv, crypto_state} <-
           decrypt(protected_data, operation, crypto_state, state, spi),
         {:ok, clear_data} <- remove_padding(clear_with_padding, header.pad_length, spi),
         next_dynamic <- next_dynamic(dynamic, received_sequence, next_iv, header, association),
         result <- result(request, association, header, encoded_header, mac, clear_data),
         next_state <-
           %{
             state
             | receiver_state: Map.put(state.receiver_state, key, next_dynamic),
               crypto_state: crypto_state
           } do
      {:ok, result, next_state}
    else
      {:error, reason} -> verification_error(:malformed_security_header, reason, nil)
      {:verification_error, _code, _reason, _spi} = error -> error
    end
  end

  defp fetch_association(request, state) do
    case request.secured_payload do
      <<spi::16, _rest::binary>> ->
        key = {request.channel.physical_channel, spi}
        find_association(key, spi, request.channel, state)

      _binary ->
        verification_error(:invalid_spi, :truncated_security_parameter_index, nil)
    end
  end

  defp find_association(key, spi, channel, state) do
    case Map.fetch(state.associations, key) do
      {:ok, association} -> validate_context(key, spi, channel, association)
      :error -> verification_error(:invalid_spi, :unknown_security_parameter_index, spi)
    end
  end

  defp validate_context(key, spi, channel, association) do
    if association.active? and channel_member?(channel, association),
      do: {:ok, key, association, spi},
      else: verification_error(:invalid_spi, :security_association_context_mismatch, spi)
  end

  defp validate_service(request, association, spi) do
    case Service.validate(request.channel, request.service, association.service_type) do
      :ok -> :ok
      {:error, reason} -> verification_error(:invalid_spi, reason, spi)
    end
  end

  defp decode_header(payload, association, spi) do
    case SecurityHeader.decode_prefix(payload, association) do
      {:ok, _header, _rest, _encoded} = result -> result
      {:error, reason} -> verification_error(:malformed_security_header, reason, spi)
    end
  end

  defp split_trailer(binary, association, spi) do
    mac_length = association.mac_length

    if byte_size(binary) >= mac_length do
      data_length = byte_size(binary) - mac_length
      <<data::binary-size(^data_length), mac::binary-size(^mac_length)>> = binary
      {:ok, data, mac}
    else
      verification_error(
        :mac_verification_failure,
        {:truncated_security_trailer, mac_length, byte_size(binary)},
        spi
      )
    end
  end

  defp operation(request, association, header, encoded_header) do
    %Operation{
      direction: :inbound,
      channel: request.channel,
      service: request.service,
      association: association,
      frame_prefix: request.frame_prefix,
      security_header: encoded_header,
      initialization_vector: header.initialization_vector,
      sequence_number: header.sequence_number,
      pad_length: header.pad_length,
      meta: request.meta
    }
  end

  defp verify_mac(_prefix, _header, _data, <<>>, %{association: association}, state)
       when association.service_type == :encryption,
       do: {:ok, state.crypto_state}

  defp verify_mac(prefix, header, data, received_mac, operation, state) do
    payload = prefix <> header <> data
    spi = operation.association.spi

    with {:ok, masked} <-
           map_error(
             AuthenticationMask.apply(
               payload,
               prefix,
               operation.channel,
               operation.service,
               operation.association
             ),
             :cryptographic_failure,
             spi
           ),
         {:ok, computed_mac, crypto_state} <-
           authenticate(masked, operation, state.crypto_state, state, spi),
         {:ok, expected_mac} <-
           map_error(
             truncate_mac(computed_mac, operation.association.mac_length),
             :cryptographic_failure,
             spi
           ),
         true <- secure_compare(expected_mac, received_mac) do
      {:ok, crypto_state}
    else
      false -> verification_error(:mac_verification_failure, :authentication_code_mismatch, spi)
      {:verification_error, _code, _reason, _spi} = error -> error
    end
  end

  defp authenticate(payload, operation, crypto_state, state, spi) do
    case state.crypto_provider.authenticate(payload, operation, crypto_state) do
      {:ok, mac, next_crypto_state} when is_binary(mac) ->
        {:ok, mac, next_crypto_state}

      {:error, reason} ->
        verification_error(
          :cryptographic_failure,
          {:crypto_provider_error, {:authenticate, :inbound}, reason},
          spi
        )

      returned ->
        verification_error(
          :cryptographic_failure,
          {:invalid_crypto_provider_return, {:authenticate, :inbound}, returned},
          spi
        )
    end
  end

  defp verify_replay(_header, association, dynamic, _spi)
       when association.service_type == :encryption,
       do: {:ok, dynamic.sequence_number}

  defp verify_replay(header, association, dynamic, spi) do
    received = received_sequence(header, association)

    case AntiReplay.verify(received, dynamic.sequence_number, association.sequence_window) do
      :ok ->
        {:ok, received}

      {:error, reason} ->
        verification_error(
          :anti_replay_sequence_number_failure,
          {reason, received, dynamic.sequence_number, association.sequence_window},
          spi
        )
    end
  end

  defp received_sequence(header, %{sequence_number_source: :sequence_number}),
    do: header.sequence_number

  defp received_sequence(header, %{sequence_number_source: :initialization_vector}),
    do: :binary.decode_unsigned(header.initialization_vector)

  defp decrypt(data, %{association: association}, crypto_state, _state, _spi)
       when association.service_type == :authentication,
       do: {:ok, data, association.initialization_vector, crypto_state}

  defp decrypt(data, operation, crypto_state, state, spi) do
    case state.crypto_provider.decrypt(data, operation, crypto_state) do
      {:ok, clear_data, next_iv, next_crypto_state} ->
        with :ok <-
               map_error(validate_binary(clear_data, :clear_data), :cryptographic_failure, spi),
             :ok <-
               map_error(
                 validate_iv(next_iv, operation.association),
                 :cryptographic_failure,
                 spi
               ) do
          {:ok, clear_data, next_iv, next_crypto_state}
        end

      {:error, :padding_error} ->
        verification_error(:padding_error, :crypto_provider_padding_error, spi)

      {:error, reason} ->
        verification_error(
          :cryptographic_failure,
          {:crypto_provider_error, :decrypt, reason},
          spi
        )

      returned ->
        verification_error(
          :cryptographic_failure,
          {:invalid_crypto_provider_return, :decrypt, returned},
          spi
        )
    end
  end

  defp remove_padding(data, 0, _spi), do: {:ok, data}

  defp remove_padding(data, pad_length, _spi) when pad_length <= byte_size(data) do
    {:ok, binary_part(data, 0, byte_size(data) - pad_length)}
  end

  defp remove_padding(data, pad_length, spi) do
    verification_error(
      :padding_error,
      {:invalid_padding_length, pad_length, byte_size(data)},
      spi
    )
  end

  defp next_dynamic(dynamic, received_sequence, next_iv, header, association) do
    dynamic =
      if SecurityAssociation.authentication?(association),
        do: %{dynamic | sequence_number: received_sequence},
        else: dynamic

    cond do
      association.sequence_number_source == :initialization_vector ->
        %{dynamic | initialization_vector: header.initialization_vector}

      SecurityAssociation.encryption?(association) ->
        %{dynamic | initialization_vector: next_iv}

      true ->
        dynamic
    end
  end

  defp result(request, association, header, encoded_header, mac, clear_data) do
    verification = %Verification{status: :success, code: :no_failure, spi: association.spi}

    %ProcessResult{
      data: clear_data,
      security_header: encoded_header,
      security_trailer: mac,
      spi: association.spi,
      initialization_vector: header.initialization_vector,
      sequence_number: header.sequence_number,
      pad_length: header.pad_length,
      verification: verification,
      meta: request.meta
    }
  end

  defp validate_request(request) do
    with :ok <- Channel.validate(request.channel),
         :ok <- validate_atom(request.service, :service),
         :ok <- validate_binary(request.frame_prefix, :frame_prefix),
         :ok <- validate_binary(request.secured_payload, :secured_payload) do
      validate_map(request.meta, :meta)
    end
  end

  defp validate_iv(value, association) do
    expected = association.initialization_vector_length

    if is_binary(value) and byte_size(value) == expected,
      do: :ok,
      else: {:error, {:initialization_vector_length_mismatch, byte_size_safe(value), expected}}
  end

  defp truncate_mac(mac, length) when is_binary(mac) and byte_size(mac) >= length,
    do: {:ok, binary_part(mac, 0, length)}

  defp truncate_mac(mac, length),
    do: {:error, {:authentication_code_too_short, byte_size_safe(mac), length}}

  defp secure_compare(left, right) when byte_size(left) == byte_size(right) do
    left
    |> :binary.bin_to_list()
    |> Enum.zip(:binary.bin_to_list(right))
    |> Enum.reduce(0, fn {left_byte, right_byte}, acc -> bor(acc, bxor(left_byte, right_byte)) end)
    |> Kernel.==(0)
  end

  defp secure_compare(_left, _right), do: false

  defp channel_member?(channel, association),
    do: Enum.any?(association.channels, &(Channel.key(&1) == Channel.key(channel)))

  defp validate_binary(value, _field) when is_binary(value), do: :ok
  defp validate_binary(value, field), do: {:error, {:invalid_field, field, value}}

  defp validate_atom(value, _field) when is_atom(value) and not is_nil(value), do: :ok
  defp validate_atom(value, field), do: {:error, {:invalid_field, field, value}}

  defp validate_map(value, _field) when is_map(value), do: :ok
  defp validate_map(value, field), do: {:error, {:invalid_field, field, value}}

  defp map_error(:ok, _code, _spi), do: :ok
  defp map_error({:ok, _value} = ok, _code, _spi), do: ok

  defp map_error({:error, reason}, code, spi),
    do: verification_error(code, reason, spi)

  defp verification_error(code, reason, spi),
    do: {:verification_error, code, reason, spi}

  defp byte_size_safe(value) when is_binary(value), do: byte_size(value)
  defp byte_size_safe(_value), do: :invalid
end
