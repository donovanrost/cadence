defmodule Cadence.CCSDS.CFDP.CodecTest do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.CFDP.{Codec, Configuration, FileData, PDU, Stream}
  alias Cadence.CCSDS.CFDP.Directive
  alias Cadence.CCSDS.CFDP.TLV

  test "encodes the core Metadata, File Data, and EOF sequence exactly" do
    metadata =
      pdu(%Directive.Metadata{
        checksum_type: 0,
        file_size: 3,
        source_file_name: "a",
        destination_file_name: "b"
      })

    file_data = pdu(%FileData{offset: 0, data: hex("AABBCC")})

    eof =
      pdu(%Directive.EndOfFile{
        file_checksum: 0xAABBCCDD,
        file_size: 3
      })

    metadata_wire = hex("24000A0001020307000000000301610162")
    file_data_wire = hex("3400070001020300000000AABBCC")
    eof_wire = hex("24000A000102030400AABBCCDD00000003")

    assert {:ok, ^metadata_wire} = Codec.encode(metadata)
    assert {:ok, ^file_data_wire} = Codec.encode(file_data)
    assert {:ok, ^eof_wire} = Codec.encode(eof)
  end

  test "round-trips every file directive and file-data form" do
    acknowledged = [
      pdu(
        %Directive.Finished{
          condition: :filestore_rejection,
          delivery_code: :incomplete,
          file_status: :discarded_by_filestore,
          filestore_responses: [
            %TLV.FilestoreResponse{
              action: :create_file,
              status: 1,
              first_file_name: "out",
              filestore_message: "denied"
            }
          ],
          fault_location: %TLV.EntityID{entity_id: 7, octets: 2}
        },
        direction: :toward_file_sender,
        mode: :acknowledged
      ),
      pdu(
        %Directive.Acknowledgement{
          directive: :end_of_file,
          condition: :no_error,
          transaction_status: :active
        },
        direction: :toward_file_sender,
        mode: :acknowledged
      ),
      pdu(
        %Directive.Acknowledgement{
          directive: :finished,
          condition: :no_error,
          transaction_status: :terminated
        },
        direction: :toward_file_receiver,
        mode: :acknowledged
      ),
      pdu(
        %Directive.NegativeAcknowledgement{
          start_of_scope: 0,
          end_of_scope: 12,
          segment_requests: [{0, 0}, {4, 8}]
        },
        direction: :toward_file_sender,
        mode: :acknowledged
      ),
      pdu(%Directive.Prompt{response: :keep_alive}, mode: :acknowledged),
      pdu(%Directive.KeepAlive{progress: 8}, direction: :toward_file_sender, mode: :acknowledged)
    ]

    unacknowledged = [
      pdu(%Directive.Metadata{
        closure_requested?: true,
        checksum_type: 15,
        file_size: 0,
        options: [
          %TLV.MessageToUser{message: "proxy"},
          %TLV.FlowLabel{value: <<1, 2>>}
        ]
      }),
      pdu(%Directive.EndOfFile{
        condition: :cancel_request_received,
        file_checksum: 0,
        file_size: 8,
        fault_location: %TLV.EntityID{entity_id: 3, octets: 1}
      }),
      pdu(
        %FileData{
          offset: 1,
          data: <<2, 3>>,
          record_continuation_state: :start_and_end,
          segment_metadata: <<0xAA>>
        },
        record_boundaries_preserved?: true
      )
    ]

    for value <- acknowledged ++ unacknowledged do
      assert {:ok, encoded} = Codec.encode(value)
      assert {:ok, decoded} = Codec.decode(encoded)
      assert {:ok, ^encoded} = Codec.encode(decoded)
      assert decoded.payload == value.payload
    end
  end

  test "supports large files, eight-octet identifiers, and the optional PDU CRC" do
    pdu =
      pdu(
        %FileData{
          offset: 0x1_0000_0000,
          data: <<1, 2, 3>>,
          segment_metadata: <<>>
        },
        large_file?: true,
        crc?: true,
        source_entity_id: 0x0102030405060708,
        destination_entity_id: 0x1112131415161718,
        transaction_sequence_number: 0x0102030405060708
      )

    assert {:ok, encoded} = Codec.encode(pdu)
    assert {:ok, decoded} = Codec.decode(encoded)
    assert decoded.entity_id_octets == 8
    assert decoded.sequence_number_octets == 8
    assert decoded.large_file?
    assert decoded.crc?
    assert decoded.payload == pdu.payload

    last = byte_size(encoded) - 1
    <<prefix::binary-size(^last), byte>> = encoded

    assert {:error, {:invalid_cfdp_crc, _expected, _received}} =
             Codec.decode(prefix <> <<Bitwise.bxor(byte, 1)>>)
  end

  test "streams complete PDUs while preserving an incomplete suffix" do
    {:ok, first} = Codec.encode(pdu(%FileData{offset: 0, data: <<1, 2>>}))
    {:ok, second} = Codec.encode(pdu(%Directive.EndOfFile{file_checksum: 3, file_size: 2}))
    split = byte_size(second) - 2
    <<prefix::binary-size(^split), suffix::binary>> = second

    assert {:ok, [decoded], ^prefix} = Stream.decode(first <> prefix)
    assert %FileData{} = decoded.payload

    assert {:ok, [_, _], <<>>} = Stream.decode(first <> prefix <> suffix)
    assert {:ok, [^first, ^second], <<>>} = Stream.extract(first <> second)
  end

  test "rejects reserved values, invalid directions, bad spare bits, and managed limits" do
    assert {:error, {:unsupported_cfdp_version, 2}} =
             Codec.decode(hex("44000A0001020307000000000301610162"))

    assert {:error, {:invalid_pdu_direction, :toward_file_sender, :toward_file_receiver}} =
             Codec.encode(pdu(%Directive.KeepAlive{progress: 1}, mode: :acknowledged))

    assert {:error, {:nonzero_spare_bits, :metadata_reserved, 1}} =
             Codec.decode(hex("24000A0001020307800000000301610162"))

    configuration = Configuration.new!(maximum_pdu_data_octets: 8)

    assert {:error, {:pdu_data_exceeds_managed_maximum, 10, 8}} =
             Codec.encode(
               pdu(%Directive.EndOfFile{file_checksum: 0, file_size: 0}),
               configuration: configuration
             )

    assert {:error, :closure_flag_must_be_zero_in_acknowledged_mode} =
             Codec.encode(pdu(%Directive.Metadata{closure_requested?: true}, mode: :acknowledged))

    assert {:error, {:pdu_data_exceeds_managed_maximum, 65_540, 65_535}} =
             Codec.encode(pdu(%FileData{offset: 0, data: :binary.copy(<<0>>, 65_536)}))
  end

  defp pdu(payload, opts \\ []) do
    %PDU{
      direction: Keyword.get(opts, :direction, :toward_file_receiver),
      transmission_mode: Keyword.get(opts, :mode, :unacknowledged),
      crc?: Keyword.get(opts, :crc?, false),
      large_file?: Keyword.get(opts, :large_file?, false),
      record_boundaries_preserved?: Keyword.get(opts, :record_boundaries_preserved?, false),
      source_entity_id: Keyword.get(opts, :source_entity_id, 1),
      transaction_sequence_number: Keyword.get(opts, :transaction_sequence_number, 2),
      destination_entity_id: Keyword.get(opts, :destination_entity_id, 3),
      payload: payload
    }
  end

  defp hex(value), do: Base.decode16!(value)
end
