defmodule Cadence.CCSDS.SDLSTest do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.SDLS.{
    AntiReplay,
    ApplyRequest,
    AuthenticationMask,
    Channel,
    ProcessRequest,
    Provider,
    SecurityAssociation,
    SecurityHeader,
    Service
  }

  alias Cadence.CCSDS.TestSupport.SDLSTestCryptoProvider

  test "encodes the baseline TC Security Header layout" do
    association = authentication_association()

    header = %SecurityHeader{
      spi: association.spi,
      initialization_vector: <<>>,
      sequence_number: 0x01020304,
      pad_length: 0
    }

    assert {:ok, encoded} = SecurityHeader.encode(header, association)
    assert encoded == hex("123401020304")

    assert {:ok, ^header, <<0xAA>>, ^encoded} =
             SecurityHeader.decode_prefix(encoded <> <<0xAA>>, association)
  end

  test "applies authentication, verifies it, and advances independent replay state" do
    association = authentication_association()
    {:ok, provider} = Provider.init([association], SDLSTestCryptoProvider)
    request = apply_request(association, <<1, 2, 3>>)

    assert {:ok, applied, sender} = Provider.apply_security(request, provider)
    assert applied.security_header == hex("123400000001")
    assert applied.data == request.data
    assert byte_size(applied.security_trailer) == 8
    assert applied.payload == applied.security_header <> applied.data <> applied.security_trailer

    assert {:ok, sender_dynamic} =
             Provider.dynamic_state(sender, :sender, "forward", association.spi)

    assert sender_dynamic.sequence_number == 1

    process = process_request(request, applied.payload)
    assert {:ok, processed, receiver} = Provider.process_security(process, sender)
    assert processed.data == request.data
    assert processed.verification.status == :success
    assert processed.verification.code == :no_failure

    assert {:ok, receiver_dynamic} =
             Provider.dynamic_state(receiver, :receiver, "forward", association.spi)

    assert receiver_dynamic.sequence_number == 1

    assert {:error, verification, ^receiver} = Provider.process_security(process, receiver)
    assert verification.code == :anti_replay_sequence_number_failure
    assert verification.reason == {:replayed, 1, 1, 10}
  end

  test "rejects a modified MAC without advancing anti-replay state" do
    association = authentication_association()
    {:ok, provider} = Provider.init([association], SDLSTestCryptoProvider)
    request = apply_request(association, <<1, 2, 3>>)
    {:ok, applied, sender} = Provider.apply_security(request, provider)
    size = byte_size(applied.payload) - 1
    <<prefix::binary-size(^size), last>> = applied.payload
    tampered = prefix <> <<Bitwise.bxor(last, 1)>>

    assert {:error, verification, ^sender} =
             Provider.process_security(process_request(request, tampered), sender)

    assert verification.code == :mac_verification_failure
  end

  test "rejects an authenticated sequence outside the managed positive window" do
    sender_association = authentication_association(sequence_number: 4, sequence_window: 2)
    receiver_association = authentication_association(sequence_number: 0, sequence_window: 2)
    {:ok, sender} = Provider.init([sender_association], SDLSTestCryptoProvider)
    {:ok, receiver} = Provider.init([receiver_association], SDLSTestCryptoProvider)
    request = apply_request(sender_association, <<9>>)
    {:ok, applied, _sender} = Provider.apply_security(request, sender)

    assert {:error, verification, ^receiver} =
             Provider.process_security(process_request(request, applied.payload), receiver)

    assert verification.code == :anti_replay_sequence_number_failure
    assert verification.reason == {:outside_window, 5, 0, 2}
  end

  test "authenticated encryption delegates crypto, carries padding, and restores clear data" do
    association = authenticated_encryption_association()
    {:ok, provider} = Provider.init([association], SDLSTestCryptoProvider)
    request = apply_request(association, <<1, 2, 3>>)

    assert {:ok, applied, sender} = Provider.apply_security(request, provider)
    assert applied.data != request.data
    assert byte_size(applied.data) == 4
    assert applied.pad_length == 1
    assert byte_size(applied.security_header) == 9
    assert byte_size(applied.security_trailer) == 8

    assert {:ok, processed, receiver} =
             Provider.process_security(process_request(request, applied.payload), sender)

    assert processed.data == request.data
    assert processed.pad_length == 1
    assert receiver.crypto_state.padding_length == 1
    assert receiver.crypto_state.encrypt == 1
    assert receiver.crypto_state.decrypt == 1
    assert receiver.crypto_state.authenticate == 2
  end

  test "the Initialization Vector can serve as the anti-replay sequence number" do
    association = iv_sequence_association()
    {:ok, provider} = Provider.init([association], SDLSTestCryptoProvider)
    request = apply_request(association, <<7, 8>>)

    assert {:ok, applied, sender} = Provider.apply_security(request, provider)
    assert applied.sequence_number == nil
    assert applied.initialization_vector == <<0::88, 1>>
    assert byte_size(applied.security_header) == 14

    assert {:ok, processed, receiver} =
             Provider.process_security(process_request(request, applied.payload), sender)

    assert processed.data == request.data

    assert {:ok, dynamic} =
             Provider.dynamic_state(receiver, :receiver, "forward", association.spi)

    assert dynamic.sequence_number == 1
    assert dynamic.initialization_vector == <<0::88, 1>>
  end

  test "SPI lookup is scoped by physical channel and exact GVCID or GMAP context" do
    association = authentication_association()
    {:ok, provider} = Provider.init([association], SDLSTestCryptoProvider)
    request = apply_request(association, <<1>>)
    {:ok, applied, provider} = Provider.apply_security(request, provider)
    wrong_channel = %{request.channel | map_id: 8}

    process = %ProcessRequest{
      channel: wrong_channel,
      service: request.service,
      frame_prefix: request.frame_prefix,
      secured_payload: applied.payload
    }

    assert {:error, verification, ^provider} = Provider.process_security(process, provider)
    assert verification.code == :invalid_spi
    assert verification.reason == :security_association_context_mismatch
  end

  test "authentication masks require SPI, sequence, pad, and Frame Data coverage" do
    association = authenticated_encryption_association()
    channel = hd(association.channels)
    frame_prefix = :binary.copy(<<0>>, 6)
    prefix = :binary.copy(<<0xFF>>, 6)
    invalid_header_mask = prefix <> :binary.copy(<<0xFF>>, 32)
    payload = :binary.copy(<<0>>, 6 + SecurityAssociation.header_length(association) + 3)
    invalid = %{association | authentication_mask: invalid_header_mask}

    assert {:error, {:invalid_security_header_authentication_mask, _actual, _expected}} =
             AuthenticationMask.apply(
               payload,
               frame_prefix,
               channel,
               :virtual_channel_packet,
               invalid
             )

    valid = %{association | authentication_mask: authentication_mask(6, association, 3)}

    assert {:ok, masked} =
             AuthenticationMask.apply(
               payload,
               frame_prefix,
               channel,
               :virtual_channel_packet,
               valid
             )

    assert byte_size(masked) == byte_size(payload)
  end

  test "enforces the protocol-specific authentication-mask requirements" do
    tc_association = authentication_association()
    tc_channel = hd(tc_association.channels)
    tc_prefix = :binary.copy(<<0>>, 6)
    tc_payload = mask_payload(tc_prefix, tc_association, 1)
    tc_mask = authentication_mask(6, tc_association, 1)
    tc_invalid = %{tc_association | authentication_mask: replace_octet(tc_mask, 5, 0)}

    assert {:error,
            {:authentication_mask_required_octets_missing, :tc_segment_header, <<0>>, <<255>>}} =
             AuthenticationMask.apply(
               tc_payload,
               tc_prefix,
               tc_channel,
               :map_packet,
               tc_invalid
             )

    tm_association = iv_sequence_association()
    tm_channel = hd(tm_association.channels)
    tm_prefix = :binary.copy(<<0>>, 6)
    tm_payload = mask_payload(tm_prefix, tm_association, 1)
    tm_mask = authentication_mask(6, tm_association, 1)
    tm_invalid = %{tm_association | authentication_mask: replace_octet(tm_mask, 2, 0xFF)}

    assert {:error,
            {:authentication_mask_forbidden_bits_set, :tm_master_channel_frame_count, 0xFF, 0xFF}} =
             AuthenticationMask.apply(
               tm_payload,
               tm_prefix,
               tm_channel,
               :virtual_channel_packet,
               tm_invalid
             )

    aos_association = authenticated_encryption_association()
    aos_channel = hd(aos_association.channels)
    aos_prefix = :binary.copy(<<0>>, 8)
    aos_payload = mask_payload(aos_prefix, aos_association, 1)

    aos_mask =
      :binary.copy(<<0xFF>>, 8) <>
        security_and_data_mask(aos_association, 1)

    aos_invalid = %{aos_association | authentication_mask: aos_mask}

    assert {:error, {:authentication_mask_forbidden_octets_set, :aos_fhec_and_insert_zone, _}} =
             AuthenticationMask.apply(
               aos_payload,
               aos_prefix,
               aos_channel,
               :virtual_channel_packet,
               aos_invalid
             )

    uslp_channel =
      Channel.new!(
        physical_channel: "return",
        protocol: :uslp,
        transfer_frame_version: 12,
        scid: 1,
        vcid: 2,
        map_id: 3
      )

    uslp_association =
      tc_association
      |> Map.from_struct()
      |> Map.put(:spi, 0x4567)
      |> Map.put(:channels, [uslp_channel])
      |> SecurityAssociation.new!()

    uslp_prefix = :binary.copy(<<0>>, 9)
    uslp_payload = mask_payload(uslp_prefix, uslp_association, 1)

    uslp_mask =
      :binary.copy(<<0xFF>>, 7) <>
        <<0, 0>> <> security_and_data_mask(uslp_association, 1)

    uslp_valid = %{uslp_association | authentication_mask: uslp_mask}

    assert {:ok, _masked} =
             AuthenticationMask.apply(
               uslp_payload,
               uslp_prefix,
               uslp_channel,
               :map_packet,
               uslp_valid
             )

    uslp_invalid = %{uslp_valid | authentication_mask: replace_octet(uslp_mask, 3, 0)}

    assert {:error,
            {:authentication_mask_required_bits_missing, :uslp_virtual_channel_and_map_id, 0,
             0xFE}} =
             AuthenticationMask.apply(
               uslp_payload,
               uslp_prefix,
               uslp_channel,
               :map_packet,
               uslp_invalid
             )
  end

  test "returns portable failures for truncated headers and trailers without changing state" do
    association = authentication_association()
    {:ok, provider} = Provider.init([association], SDLSTestCryptoProvider)
    request = apply_request(association, <<1>>)

    assert {:error, invalid_spi, ^provider} =
             Provider.process_security(process_request(request, <<0x12>>), provider)

    assert invalid_spi.code == :invalid_spi
    assert invalid_spi.reason == :truncated_security_parameter_index

    assert {:error, truncated_header, ^provider} =
             Provider.process_security(
               process_request(request, <<association.spi::16, 0, 0>>),
               provider
             )

    assert truncated_header.code == :malformed_security_header
    assert truncated_header.reason == {:truncated_security_header, 6, 4}

    header = <<association.spi::16, 1::32>>

    assert {:error, truncated_trailer, ^provider} =
             Provider.process_security(
               process_request(request, header <> :binary.copy(<<0>>, 7)),
               provider
             )

    assert truncated_trailer.code == :mac_verification_failure
    assert truncated_trailer.reason == {:truncated_security_trailer, 8, 7}
  end

  test "reports decryption padding failures without advancing receiver state" do
    association = encryption_association()
    {:ok, provider} = Provider.init([association], SDLSTestCryptoProvider)
    request = apply_request(association, <<1, 2, 3>>)
    {:ok, applied, sender} = Provider.apply_security(request, provider)
    <<header_without_pad::binary-size(6), _pad_length, encrypted::binary>> = applied.payload
    malformed = header_without_pad <> <<5>> <> encrypted

    assert {:error, verification, ^sender} =
             Provider.process_security(process_request(request, malformed), sender)

    assert verification.code == :padding_error
    assert verification.reason == :crypto_provider_padding_error
  end

  test "validates SA ranges, active-channel uniqueness, and service restrictions" do
    assert {:error, {:invalid_field, :spi, 0}} =
             SecurityAssociation.new(
               Map.from_struct(authentication_association())
               |> Map.put(:spi, 0)
             )

    first = authentication_association(spi: 10)
    second = authentication_association(spi: 11)

    assert {:error, {:multiple_active_security_associations, _channel}} =
             Provider.init([first, second], SDLSTestCryptoProvider)

    assert :ok = Service.validate(:tc, :map_packet, :authentication)

    assert {:error, {:sdls_service_not_protected, :tc, :master_channel_frame, :authentication}} =
             Service.validate(:tc, :master_channel_frame, :authentication)

    assert :ok = Service.validate(:tm, :virtual_channel_secondary_header, :authentication)

    assert {:error,
            {:sdls_service_not_protected, :tm, :virtual_channel_secondary_header,
             :authenticated_encryption}} =
             Service.validate(
               :tm,
               :virtual_channel_secondary_header,
               :authenticated_encryption
             )
  end

  test "validates standard channel versions, OID exclusion, and SA VC scope" do
    assert {:error, {:invalid_transfer_frame_version, :aos, 0}} =
             Channel.new(
               physical_channel: "forward",
               protocol: :aos,
               transfer_frame_version: 0,
               scid: 1,
               vcid: 1
             )

    assert {:error, :sdls_forbidden_on_only_idle_data} =
             Channel.new(
               physical_channel: "forward",
               protocol: :uslp,
               transfer_frame_version: 12,
               scid: 1,
               vcid: 63,
               map_id: 1
             )

    tc_first = channel(:tc, 0, 1)
    tc_second = %{tc_first | vcid: tc_first.vcid + 1}

    tc_attrs =
      Map.from_struct(authentication_association()) |> Map.put(:channels, [tc_first, tc_second])

    assert {:error, {:security_association_spans_virtual_channels, :tc, _channels}} =
             SecurityAssociation.new(tc_attrs)

    uslp_first =
      Channel.new!(
        physical_channel: "return",
        protocol: :uslp,
        transfer_frame_version: 12,
        scid: 1,
        vcid: 1,
        map_id: 1,
        cop_in_use?: true
      )

    uslp_second = %{uslp_first | vcid: 2}

    uslp_attrs =
      Map.from_struct(authentication_association())
      |> Map.put(:channels, [uslp_first, uslp_second])

    assert {:error, {:security_association_spans_virtual_channels, :uslp_cop, _channels}} =
             SecurityAssociation.new(uslp_attrs)

    assert {:error, {:sdls_map_id_required, :tc, :map_packet}} =
             Service.validate(%{tc_first | map_id: nil}, :map_packet, :authentication)
  end

  test "anti-replay rejects replay, window overflow, and unspecified rollover" do
    assert :ok = AntiReplay.verify(6, 5, 3)
    assert {:error, :replayed} = AntiReplay.verify(5, 5, 3)
    assert {:error, :outside_window} = AntiReplay.verify(9, 5, 3)
    assert {:ok, 65_535} = AntiReplay.next(65_534, 2)
    assert {:error, :sequence_number_rollover} = AntiReplay.next(65_535, 2)
  end

  defp authentication_association(overrides \\ []) do
    channel = channel(:tc, 0, 7)

    attrs = [
      spi: 0x1234,
      channels: [channel],
      service_type: :authentication,
      active?: true,
      sequence_number_length: 4,
      mac_length: 8,
      authentication_algorithm: :test_hash,
      authentication_key_ref: {:key, 1},
      authentication_mask: :binary.copy(<<0xFF>>, 256),
      sequence_number: 0,
      sequence_window: 10,
      sequence_number_source: :sequence_number
    ]

    SecurityAssociation.new!(Keyword.merge(attrs, overrides))
  end

  defp authenticated_encryption_association do
    channel = channel(:aos, 1, nil)

    association =
      SecurityAssociation.new!(
        spi: 0x2345,
        channels: [channel],
        service_type: :authenticated_encryption,
        active?: true,
        initialization_vector_length: 4,
        sequence_number_length: 2,
        pad_length_length: 1,
        mac_length: 8,
        authentication_algorithm: :test_hash,
        authentication_key_ref: {:key, 2},
        authentication_mask: <<>>,
        sequence_number: 0,
        sequence_window: 10,
        sequence_number_source: :sequence_number,
        encryption_algorithm: :xor_padded,
        encryption_key_ref: {:key, 3},
        initialization_vector: <<0, 0, 0, 1>>
      )

    %{association | authentication_mask: authentication_mask(6, association, 256)}
  end

  defp encryption_association do
    SecurityAssociation.new!(
      spi: 0x2346,
      channels: [channel(:aos, 1, nil)],
      service_type: :encryption,
      active?: true,
      initialization_vector_length: 4,
      pad_length_length: 1,
      encryption_algorithm: :xor_padded,
      encryption_key_ref: {:key, 6},
      initialization_vector: <<0, 0, 0, 1>>
    )
  end

  defp iv_sequence_association do
    channel = channel(:tm, 0, nil)
    iv = <<0::96>>

    association =
      SecurityAssociation.new!(
        spi: 0x3456,
        channels: [channel],
        service_type: :authenticated_encryption,
        active?: true,
        initialization_vector_length: 12,
        sequence_number_length: 0,
        mac_length: 8,
        authentication_algorithm: :test_hash,
        authentication_key_ref: {:key, 4},
        authentication_mask: <<>>,
        sequence_number: 0,
        sequence_window: 10,
        sequence_number_source: :initialization_vector,
        encryption_algorithm: :xor,
        encryption_key_ref: {:key, 5},
        initialization_vector: iv
      )

    %{association | authentication_mask: authentication_mask(6, association, 256)}
  end

  defp apply_request(association, data) do
    channel = hd(association.channels)

    %ApplyRequest{
      channel: channel,
      service: service(channel.protocol),
      frame_prefix: <<0x20, 0x2A, 0x14, 0x07, 0x4D, 0xC7>>,
      data: data,
      meta: %{frame_id: 9}
    }
  end

  defp process_request(request, payload) do
    %ProcessRequest{
      channel: request.channel,
      service: request.service,
      frame_prefix: request.frame_prefix,
      secured_payload: payload,
      meta: request.meta
    }
  end

  defp channel(protocol, version, map_id) do
    Channel.new!(
      physical_channel: "forward",
      protocol: protocol,
      transfer_frame_version: version,
      scid: 42,
      vcid: 3,
      map_id: map_id
    )
  end

  defp authentication_mask(prefix_octets, association, data_octets) do
    prefix = prefix_authentication_mask(prefix_octets, hd(association.channels).protocol)
    prefix <> security_and_data_mask(association, data_octets)
  end

  defp prefix_authentication_mask(prefix_octets, :tm) when prefix_octets >= 6 do
    <<0xFF, 0xFF, 0, 0xFF, 0xFF, 0xFF>> <>
      :binary.copy(<<0xFF>>, prefix_octets - 6)
  end

  defp prefix_authentication_mask(prefix_octets, _protocol),
    do: :binary.copy(<<0xFF>>, prefix_octets)

  defp security_and_data_mask(association, data_octets) do
    spi = <<0xFF, 0xFF>>
    iv = :binary.copy(<<0>>, association.initialization_vector_length)

    sequence_and_pad =
      :binary.copy(
        <<0xFF>>,
        association.sequence_number_length + association.pad_length_length
      )

    data = :binary.copy(<<0xFF>>, data_octets)
    spi <> iv <> sequence_and_pad <> data
  end

  defp mask_payload(prefix, association, data_octets) do
    prefix <>
      :binary.copy(<<0>>, SecurityAssociation.header_length(association) + data_octets)
  end

  defp replace_octet(binary, offset, value) do
    <<prefix::binary-size(^offset), _old, suffix::binary>> = binary
    prefix <> <<value>> <> suffix
  end

  defp service(:tm), do: :virtual_channel_packet
  defp service(:tc), do: :map_packet
  defp service(:aos), do: :virtual_channel_packet
  defp service(:uslp), do: :map_packet

  defp hex(value), do: Base.decode16!(value)
end
