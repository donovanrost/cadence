defmodule Cadence.Runtime.CommandingBoundaryTest do
  use ExUnit.Case, async: true

  alias Cadence.Catalog.Command.Compiler.RuntimeDefinition
  alias Cadence.Runtime.Commanding
  alias Cadence.Runtime.TransmitCommand

  test "encodes an immutable command definition without Control or Repo" do
    assert Process.whereis(Cadence.Control.Supervisor) == nil
    assert Process.whereis(Cadence.Repo) == nil

    definition =
      RuntimeDefinition.new(%{
        command_id: "command-1",
        snapshot_id: "snapshot-1",
        name: "NOOP",
        layout_id: "layout-1",
        layout_kind: :raw_payload,
        byte_order: :big_endian,
        opcode: 0x42,
        opcode_size_bits: 8
      })

    assert {:ok, encoded} = Commanding.encode(definition, %{})
    assert encoded.binary == <<0x42>>
    assert encoded.base64 == Base.encode64(<<0x42>>)
  end

  test "validates exact transmit bytes and content identity" do
    occurred_at = DateTime.utc_now()

    attrs = %{
      transmit_request_id: "attempt-1",
      mission_id: "mission-1",
      realized_contact_id: "contact-1",
      path_id: "uplink-1",
      transport_binding_id: "gateway-1",
      occurred_at: occurred_at,
      command_queue_entry_id: "queue-1",
      command_request_id: "request-1",
      source_endpoint_ref: "endpoint-1",
      command_snapshot_id: "snapshot-1",
      command_id: "command-1",
      encoded_binary_base64: Base.encode64(<<1, 2, 3>>),
      encoded_size_bytes: 3,
      metadata: %{}
    }

    assert {:ok, request} = TransmitCommand.new(attrs)

    assert request.content_sha256 ==
             Base.encode16(:crypto.hash(:sha256, <<1, 2, 3>>), case: :lower)

    assert {:error, :transmit_command_size_mismatch} =
             TransmitCommand.new(%{attrs | encoded_size_bytes: 2})
  end
end
