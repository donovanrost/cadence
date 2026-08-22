defmodule Cadence.CCSDS.CFDP.Class1Test do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.CFDP.{Checksum, FileData, FileEffect, PDU}
  alias Cadence.CCSDS.CFDP.Class1.{Receiver, Sender}

  alias Cadence.CCSDS.CFDP.Directive.{EndOfFile, Finished, Metadata}

  test "completes a closure-requested transfer with out-of-order delivery" do
    assert {:ok, sender} =
             Sender.new(
               source_entity_id: 1,
               transaction_sequence_number: 9,
               destination_entity_id: 3,
               source_file_name: "source.bin",
               destination_file_name: "received.bin",
               file: <<0, 1, 2, 3, 4, 5, 6>>,
               segment_octets: 3,
               closure_requested?: true,
               check_limit: 2
             )

    assert {:ok, metadata_transition} = Sender.next(sender)
    assert [%PDU{payload: %Metadata{}} = metadata] = metadata_transition.pdus

    assert {:ok, first_transition} = Sender.next(metadata_transition.state)
    assert [%PDU{payload: %FileData{offset: 0}} = first] = first_transition.pdus

    assert {:ok, second_transition} = Sender.next(first_transition.state)
    assert [%PDU{payload: %FileData{offset: 3}} = second] = second_transition.pdus

    assert {:ok, third_transition} = Sender.next(second_transition.state)
    assert [%PDU{payload: %FileData{offset: 6}} = third] = third_transition.pdus

    assert {:ok, eof_transition} = Sender.next(third_transition.state)
    assert [%PDU{payload: %EndOfFile{}} = eof] = eof_transition.pdus
    assert eof_transition.state.phase == :waiting_finished
    assert eof_transition.timers == [{:start, :check}]

    assert {:ok, receiver} = Receiver.new(3, check_limit: 2)

    assert {:ok, receive_eof} = Receiver.ingest(receiver, eof)
    assert receive_eof.state.phase == :checking
    assert receive_eof.timers == [{:start, :check}]

    assert {:ok, receive_third} = Receiver.ingest(receive_eof.state, third)
    assert {:ok, receive_first} = Receiver.ingest(receive_third.state, first)
    assert {:ok, receive_second} = Receiver.ingest(receive_first.state, second)
    assert {:ok, completed} = Receiver.ingest(receive_second.state, metadata)

    assert completed.state.phase == :completed
    assert [%PDU{payload: %Finished{condition: :no_error}} = finished] = completed.pdus
    assert [{:cancel, :check}] = completed.timers

    indication = List.last(completed.indications)
    assert indication.type == :transaction_finished
    assert indication.details.file == <<0, 1, 2, 3, 4, 5, 6>>

    assert {:ok, sender_completed} = Sender.ingest(eof_transition.state, finished)
    assert sender_completed.state.phase == :completed
    assert sender_completed.timers == [{:cancel, :check}]
  end

  test "completes an empty file without closure when EOF is sent" do
    assert {:ok, sender} =
             Sender.new(
               source_entity_id: 1,
               transaction_sequence_number: 10,
               destination_entity_id: 3,
               file: <<>>
             )

    assert {:ok, metadata} = Sender.next(sender)
    assert metadata.state.phase == :eof
    assert {:ok, eof} = Sender.next(metadata.state)
    assert eof.state.phase == :completed
    assert [%{type: :transaction_finished}] = eof.indications
  end

  test "faults when the Class 1 Check limit is reached" do
    assert {:ok, sender} =
             Sender.new(
               source_entity_id: 1,
               transaction_sequence_number: 11,
               destination_entity_id: 3,
               file: <<1>>,
               closure_requested?: true,
               check_limit: 1
             )

    assert {:ok, metadata} = Sender.next(sender)
    assert {:ok, data} = Sender.next(metadata.state)
    assert {:ok, eof} = Sender.next(data.state)
    assert {:ok, fault} = Sender.timer_expired(eof.state, :check)
    assert fault.state.phase == :faulted

    assert [%{type: :transaction_fault, details: %{condition: :check_limit_reached}}] =
             fault.indications
  end

  test "treats conflicting retransmitted octets as invalid file structure" do
    metadata = incoming(%Metadata{checksum_type: 15, file_size: 2})
    first = incoming(%FileData{offset: 0, data: <<1, 2>>})
    conflict = incoming(%FileData{offset: 1, data: <<9>>})

    assert {:ok, receiver} = Receiver.new(3)
    assert {:ok, with_metadata} = Receiver.ingest(receiver, metadata)
    assert {:ok, with_data} = Receiver.ingest(with_metadata.state, first)
    assert {:ok, fault} = Receiver.ingest(with_data.state, conflict)
    assert fault.state.phase == :faulted
    assert [%{details: %{condition: :invalid_file_structure}}] = fault.indications
  end

  test "streams an external source through caller-owned read effects" do
    file = <<0, 1, 2, 3, 4>>
    assert {:ok, checksum} = Checksum.compute(0, file)

    assert {:ok, sender} =
             Sender.new(
               source_entity_id: 1,
               transaction_sequence_number: 13,
               destination_entity_id: 3,
               source: {:object, "source.bin"},
               file_size: byte_size(file),
               file_checksum: checksum,
               segment_octets: 3
             )

    assert sender.file == nil
    assert {:ok, metadata} = Sender.next(sender)
    assert {:ok, read_first} = Sender.next(metadata.state)

    assert [
             %FileEffect{
               operation: :read,
               reference: {:object, "source.bin"},
               offset: 0,
               length: 3
             }
           ] = read_first.effects

    assert read_first.pdus == []
    assert {:ok, first} = Sender.supply_read(read_first.state, <<0, 1, 2>>)
    assert [%PDU{payload: %FileData{offset: 0, data: <<0, 1, 2>>}}] = first.pdus

    assert {:ok, read_second} = Sender.next(first.state)
    assert [%FileEffect{operation: :read, offset: 3, length: 2}] = read_second.effects
    assert {:ok, second} = Sender.supply_read(read_second.state, <<3, 4>>)
    assert [%PDU{payload: %FileData{offset: 3, data: <<3, 4>>}}] = second.pdus
    assert second.state.phase == :eof
  end

  test "streams received data to an external sink and verifies before finalizing" do
    file = <<1, 2, 3, 4>>
    assert {:ok, checksum} = Checksum.compute(0, file)
    metadata = incoming(%Metadata{checksum_type: 0, file_size: byte_size(file)})
    data = incoming(%FileData{offset: 0, data: file})
    eof = incoming(%EndOfFile{file_checksum: checksum, file_size: byte_size(file)})

    assert {:ok, receiver} = Receiver.new(3, sink: {:staging, "received.bin"})
    assert {:ok, with_metadata} = Receiver.ingest(receiver, metadata)
    assert {:ok, with_data} = Receiver.ingest(with_metadata.state, data)

    assert [
             %FileEffect{
               operation: :write,
               reference: {:staging, "received.bin"},
               offset: 0,
               data: ^file
             }
           ] = with_data.effects

    assert with_data.state.segments == []
    assert {:ok, verifying} = Receiver.ingest(with_data.state, eof)
    assert verifying.state.phase == :verifying

    assert [
             %FileEffect{
               operation: :checksum,
               details: %{checksum_type: 0, expected_checksum: ^checksum}
             }
           ] = verifying.effects

    assert {:ok, finalizing} = Receiver.checksum_result(verifying.state, {:ok, checksum})
    assert finalizing.state.phase == :finalizing
    assert [%FileEffect{operation: :finalize}] = finalizing.effects

    assert {:ok, completed} = Receiver.finalize_result(finalizing.state, :ok)
    assert completed.state.phase == :completed
    assert [%{type: :transaction_finished, details: details}] = completed.indications
    refute Map.has_key?(details, :file)
  end

  defp incoming(payload) do
    %PDU{
      direction: :toward_file_receiver,
      transmission_mode: :unacknowledged,
      source_entity_id: 1,
      transaction_sequence_number: 12,
      destination_entity_id: 3,
      entity_id_octets: 1,
      sequence_number_octets: 1,
      payload: payload
    }
  end
end
