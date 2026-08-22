defmodule Cadence.CCSDS.CFDP.TLV.CodecTest do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.CFDP.TLV
  alias Cadence.CCSDS.CFDP.TLV.Codec

  test "round-trips every standard TLV form" do
    values = [
      %TLV.FilestoreRequest{
        action: :rename_file,
        first_file_name: "/a",
        second_file_name: "/b"
      },
      %TLV.FilestoreResponse{
        action: :append_file,
        status: 1,
        first_file_name: "/a",
        second_file_name: "/b",
        filestore_message: "failed"
      },
      %TLV.MessageToUser{message: <<0, 1, 2>>},
      %TLV.FaultHandlerOverride{condition: :file_checksum_failure, handler: :cancel},
      %TLV.FlowLabel{value: "priority-a"},
      %TLV.EntityID{entity_id: 0x0102, octets: 3}
    ]

    assert {:ok, encoded} = Codec.encode_all(values)
    assert {:ok, decoded} = Codec.decode_all(encoded)
    assert decoded == values
  end

  test "encodes the filestore request layout exactly" do
    request = %TLV.FilestoreRequest{
      action: :rename_file,
      first_file_name: "/a",
      second_file_name: "/b"
    }

    expected = hex("000720022F61022F62")
    assert {:ok, ^expected} = Codec.encode(request)
  end

  test "rejects reserved, truncated, and semantically incomplete TLVs" do
    assert {:error, {:unsupported_cfdp_tlv_type, 3}} = Codec.decode(hex("0300"))
    assert {:error, {:truncated_tlv, 2, 4, 2}} = Codec.decode(hex("0204AABB"))

    assert {:error, {:second_file_name_required, :rename_file}} =
             Codec.encode(%TLV.FilestoreRequest{
               action: :rename_file,
               first_file_name: "/a"
             })

    assert {:error, {:nonzero_spare_bits, :filestore_request, 1}} =
             Codec.decode(hex("0003010161"))

    assert {:error, {:invalid_filestore_status, :create_file, 2}} =
             Codec.encode(%TLV.FilestoreResponse{
               action: :create_file,
               status: 2,
               first_file_name: "/a"
             })

    assert {:error, {:invalid_field, :fault_condition, :suspend_request_received}} =
             Codec.encode(%TLV.FaultHandlerOverride{
               condition: :suspend_request_received,
               handler: :ignore
             })

    assert {:error, {:invalid_field, :entity_id, nil}} = Codec.encode(%TLV.EntityID{})
  end

  defp hex(value), do: Base.decode16!(value)
end
