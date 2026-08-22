defmodule Cadence.CCSDS.CFDP.UserOperationTest do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.CFDP.TLV
  alias Cadence.CCSDS.CFDP.TransactionID
  alias Cadence.CCSDS.CFDP.UserOperation.Codec

  alias Cadence.CCSDS.CFDP.UserOperation.{
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

  test "round-trips every typed proxy and directory message" do
    operations = [
      %ProxyPutRequest{
        destination_entity_id: 0x1234,
        destination_entity_id_octets: 2,
        source_file_name: "source.bin",
        destination_file_name: "received.bin"
      },
      %ProxyMessageToUser{message: <<0, 1, 2>>},
      %ProxyFilestoreRequest{
        request: %TLV.FilestoreRequest{
          action: :rename_file,
          first_file_name: "old",
          second_file_name: "new"
        }
      },
      %ProxyFaultHandlerOverride{
        override: %TLV.FaultHandlerOverride{
          condition: :file_checksum_failure,
          handler: :suspend
        }
      },
      %ProxyTransmissionMode{transmission_mode: :unacknowledged},
      %ProxyFlowLabel{value: <<0xAA, 0xBB>>},
      %ProxySegmentationControl{record_boundaries_preserved?: false},
      %ProxyPutResponse{
        condition: :file_checksum_failure,
        delivery_code: :incomplete,
        file_status: :discarded_by_filestore
      },
      %ProxyFilestoreResponse{
        response: %TLV.FilestoreResponse{
          action: :delete_file,
          status: 0,
          first_file_name: "old",
          filestore_message: "removed"
        }
      },
      %ProxyPutCancel{},
      %OriginatingTransactionID{
        transaction_id: TransactionID.new(0x1234, 9),
        entity_id_octets: 2,
        sequence_number_octets: 1
      },
      %ProxyClosureRequest{closure_requested?: true},
      %DirectoryListingRequest{
        directory_name: "/data",
        directory_file_name: "listing.txt"
      },
      %DirectoryListingResponse{
        listing_response: :unsuccessful,
        directory_name: "/data",
        directory_file_name: "listing.txt"
      }
    ]

    for operation <- operations do
      assert {:ok, %TLV.MessageToUser{} = tlv} = Codec.encode(operation)
      assert {:ok, ^operation} = Codec.decode(tlv)
    end
  end

  test "uses the standard reserved-message identifiers and layouts" do
    request = %ProxyPutRequest{
      destination_entity_id: 3,
      destination_entity_id_octets: 1,
      source_file_name: "a",
      destination_file_name: "b"
    }

    assert {:ok, %TLV.MessageToUser{message: <<"cfdp", 0x00, 1, 3, 1, "a", 1, "b">>}} =
             Codec.encode(request)

    originating = %OriginatingTransactionID{
      transaction_id: TransactionID.new(1, 9),
      entity_id_octets: 2,
      sequence_number_octets: 1
    }

    assert {:ok, %TLV.MessageToUser{message: <<"cfdp", 0x0A, 0x10, 0, 1, 9>>}} =
             Codec.encode(originating)

    response = %DirectoryListingResponse{
      listing_response: :unsuccessful,
      directory_name: "x",
      directory_file_name: "y"
    }

    assert {:ok, %TLV.MessageToUser{message: <<"cfdp", 0x11, 0x80, 1, "x", 1, "y">>}} =
             Codec.encode(response)
  end

  test "strictly rejects non-reserved messages, spare bits, and trailing content" do
    assert {:error, :not_reserved_cfdp_message} = Codec.decode(%TLV.MessageToUser{message: "app"})

    assert {:error, {:malformed_user_operation, :proxy_transmission_mode, _content}} =
             Codec.decode(<<"cfdp", 0x04, 0x80>>)

    assert {:error, {:malformed_user_operation, :proxy_put_cancel, <<0>>}} =
             Codec.decode(<<"cfdp", 0x09, 0>>)

    assert {:error, {:unsupported_reserved_cfdp_message_type, 0x7F}} =
             Codec.decode(<<"cfdp", 0x7F>>)
  end
end
