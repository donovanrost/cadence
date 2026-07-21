defmodule Cadence.CCSDS.SDLS.AuthenticationMask do
  @moduledoc """
  Applies and validates the managed SDLS authentication bit mask.

  The helper enforces the standard-required masks for protocol header fields,
  the Security Header, and Frame Data. Header fields that the standard leaves
  to mission policy retain the exact mask selected by the Security Association.
  """

  import Bitwise

  alias Cadence.CCSDS.SDLS.{Channel, SecurityAssociation}

  @spec apply(binary(), binary(), Channel.t(), atom(), SecurityAssociation.t()) ::
          {:ok, binary()} | {:error, term()}
  def apply(
        payload,
        frame_prefix,
        %Channel{} = channel,
        service,
        %SecurityAssociation{} = association
      )
      when is_binary(payload) and is_binary(frame_prefix) and is_atom(service) do
    mask = association.authentication_mask
    prefix_octets = byte_size(frame_prefix)

    with :ok <- validate_payload_prefix(payload, frame_prefix),
         :ok <- validate_size(mask, payload),
         :ok <- validate_protocol_prefix(mask, frame_prefix, channel, service),
         :ok <- validate_security_header(mask, prefix_octets, association),
         :ok <- validate_frame_data(mask, prefix_octets, byte_size(payload), association) do
      masked = mask |> binary_part(0, byte_size(payload)) |> mask_payload(payload, [])
      {:ok, IO.iodata_to_binary(Enum.reverse(masked))}
    end
  end

  defp validate_payload_prefix(payload, prefix) do
    prefix_octets = byte_size(prefix)

    if byte_size(payload) >= prefix_octets and
         binary_part(payload, 0, prefix_octets) == prefix,
       do: :ok,
       else: {:error, :authentication_payload_prefix_mismatch}
  end

  defp validate_size(mask, payload) when is_binary(mask) do
    if byte_size(mask) >= byte_size(payload),
      do: :ok,
      else: {:error, {:authentication_mask_too_short, byte_size(mask), byte_size(payload)}}
  end

  defp validate_size(value, _payload), do: {:error, {:invalid_authentication_mask, value}}

  defp validate_protocol_prefix(mask, prefix, %Channel{protocol: :tm}, service) do
    with :ok <- validate_prefix_length(prefix, 6, :tm),
         :ok <- require_bits(mask, 1, 0x0E, :tm_virtual_channel_id),
         :ok <- forbid_bits(mask, 2, 0xFF, :tm_master_channel_frame_count) do
      if service == :virtual_channel_secondary_header,
        do: require_octets(mask, 6, byte_size(prefix) - 6, :tm_virtual_channel_secondary_header),
        else: :ok
    end
  end

  defp validate_protocol_prefix(mask, prefix, %Channel{protocol: :tc, map_id: map_id}, _service) do
    expected = if(is_nil(map_id), do: 5, else: 6)

    with :ok <- validate_exact_prefix_length(prefix, expected, :tc),
         :ok <- require_bits(mask, 2, 0xFC, :tc_virtual_channel_id) do
      if is_nil(map_id),
        do: :ok,
        else: require_octets(mask, 5, 1, :tc_segment_header)
    end
  end

  defp validate_protocol_prefix(mask, prefix, %Channel{protocol: :aos}, _service) do
    with :ok <- validate_prefix_length(prefix, 6, :aos),
         :ok <- require_bits(mask, 1, 0x3F, :aos_virtual_channel_id) do
      forbid_octets(mask, 6, byte_size(prefix) - 6, :aos_fhec_and_insert_zone)
    end
  end

  defp validate_protocol_prefix(mask, prefix, %Channel{protocol: :uslp}, _service) do
    with :ok <- validate_prefix_length(prefix, 7, :uslp),
         count_octets = band(:binary.at(prefix, 6), 0x07),
         primary_header_octets = 7 + count_octets,
         :ok <- validate_prefix_length(prefix, primary_header_octets, :uslp),
         :ok <- require_bits(mask, 2, 0x07, :uslp_virtual_channel_id),
         :ok <- require_bits(mask, 3, 0xFE, :uslp_virtual_channel_and_map_id) do
      forbid_octets(
        mask,
        primary_header_octets,
        byte_size(prefix) - primary_header_octets,
        :uslp_insert_zone
      )
    end
  end

  defp validate_prefix_length(prefix, minimum, protocol) do
    if byte_size(prefix) >= minimum,
      do: :ok,
      else: {:error, {:truncated_sdls_frame_prefix, protocol, minimum, byte_size(prefix)}}
  end

  defp validate_exact_prefix_length(prefix, expected, protocol) do
    if byte_size(prefix) == expected,
      do: :ok,
      else: {:error, {:sdls_frame_prefix_length_mismatch, protocol, expected, byte_size(prefix)}}
  end

  defp require_bits(mask, offset, required, field) do
    actual = :binary.at(mask, offset)

    if band(actual, required) == required,
      do: :ok,
      else: {:error, {:authentication_mask_required_bits_missing, field, actual, required}}
  end

  defp forbid_bits(mask, offset, forbidden, field) do
    actual = :binary.at(mask, offset)

    if band(actual, forbidden) == 0,
      do: :ok,
      else: {:error, {:authentication_mask_forbidden_bits_set, field, actual, forbidden}}
  end

  defp require_octets(_mask, _offset, 0, _field), do: :ok

  defp require_octets(mask, offset, length, field) do
    actual = binary_part(mask, offset, length)
    expected = :binary.copy(<<0xFF>>, length)

    if actual == expected,
      do: :ok,
      else: {:error, {:authentication_mask_required_octets_missing, field, actual, expected}}
  end

  defp forbid_octets(_mask, _offset, 0, _field), do: :ok

  defp forbid_octets(mask, offset, length, field) do
    actual = binary_part(mask, offset, length)
    expected = :binary.copy(<<0>>, length)

    if actual == expected,
      do: :ok,
      else: {:error, {:authentication_mask_forbidden_octets_set, field, actual}}
  end

  defp validate_security_header(mask, prefix_octets, association) do
    header_length = SecurityAssociation.header_length(association)
    actual = binary_part(mask, prefix_octets, header_length)

    expected =
      :binary.copy(<<0xFF>>, 2) <>
        :binary.copy(<<0>>, association.initialization_vector_length) <>
        :binary.copy(
          <<0xFF>>,
          association.sequence_number_length + association.pad_length_length
        )

    if actual == expected,
      do: :ok,
      else: {:error, {:invalid_security_header_authentication_mask, actual, expected}}
  end

  defp validate_frame_data(mask, prefix_octets, payload_octets, association) do
    offset = prefix_octets + SecurityAssociation.header_length(association)
    length = payload_octets - offset
    actual = binary_part(mask, offset, length)
    expected = :binary.copy(<<0xFF>>, length)

    if actual == expected,
      do: :ok,
      else: {:error, :frame_data_must_be_authenticated}
  end

  defp mask_payload(<<>>, <<>>, acc), do: acc

  defp mask_payload(<<mask, mask_rest::binary>>, <<value, value_rest::binary>>, acc),
    do: mask_payload(mask_rest, value_rest, [<<band(mask, value)>> | acc])
end
