defmodule Cadence.CCSDS.CFDP.Class2Test do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.CFDP.{Checksum, Codec, FaultPolicy, FileData, FileEffect, PDU}
  alias Cadence.CCSDS.CFDP.Class2.{Receiver, Sender}

  alias Cadence.CCSDS.CFDP.Directive.{
    Acknowledgement,
    EndOfFile,
    Finished,
    KeepAlive,
    Metadata,
    NegativeAcknowledgement,
    Prompt
  }

  test "repairs a missing segment and completes the acknowledged handshake" do
    assert {:ok, sender} =
             Sender.new(
               source_entity_id: 1,
               transaction_sequence_number: 21,
               destination_entity_id: 3,
               source_file_name: "source.bin",
               destination_file_name: "received.bin",
               file: <<0, 1, 2, 3, 4, 5, 6>>,
               segment_octets: 3,
               positive_ack_limit: 2
             )

    {sender, [metadata, first, second, third, eof]} = initial_pdus(sender)
    assert %Metadata{} = metadata.payload
    assert %FileData{offset: 0} = first.payload
    assert %FileData{offset: 3} = second.payload
    assert %FileData{offset: 6} = third.payload
    assert %EndOfFile{} = eof.payload
    assert sender.phase == :waiting_eof_ack

    assert {:ok, receiver} = Receiver.new(3, nak_limit: 2, positive_ack_limit: 2)
    assert {:ok, r1} = Receiver.ingest(receiver, metadata)
    assert {:ok, r2} = Receiver.ingest(r1.state, first)
    assert {:ok, r3} = Receiver.ingest(r2.state, third)
    assert {:ok, deferred_nak} = Receiver.ingest(r3.state, eof)

    assert [
             %PDU{payload: %Acknowledgement{directive: :end_of_file}} = eof_ack,
             %PDU{payload: %NegativeAcknowledgement{segment_requests: [{3, 6}]}} = nak
           ] = deferred_nak.pdus

    assert deferred_nak.state.phase == :waiting_repair
    assert deferred_nak.timers == [{:start, :nak}]

    assert {:ok, eof_acknowledged} = Sender.ingest(sender, eof_ack)
    assert eof_acknowledged.state.phase == :waiting_finished
    assert eof_acknowledged.timers == [{:cancel, :positive_ack}]

    assert {:ok, repair} = Sender.ingest(eof_acknowledged.state, nak)
    assert [%PDU{payload: %FileData{offset: 3, data: <<3, 4, 5>>}} = replacement] = repair.pdus

    assert {:ok, receiver_finished} = Receiver.ingest(deferred_nak.state, replacement)
    assert [%PDU{payload: %Finished{condition: :no_error}} = finished] = receiver_finished.pdus
    assert receiver_finished.state.phase == :waiting_finished_ack
    assert receiver_finished.timers == [{:cancel, :nak}, {:start, :positive_ack}]

    assert {:ok, sender_finished} = Sender.ingest(repair.state, finished)

    assert [%PDU{payload: %Acknowledgement{directive: :finished}} = finished_ack] =
             sender_finished.pdus

    assert sender_finished.state.phase == :completed

    assert {:ok, receiver_completed} = Receiver.ingest(receiver_finished.state, finished_ack)
    assert receiver_completed.state.phase == :completed

    assert [%{type: :transaction_finished, details: %{file: file}}] =
             receiver_completed.indications

    assert file == <<0, 1, 2, 3, 4, 5, 6>>

    for pdu <- [
          metadata,
          first,
          second,
          third,
          eof,
          eof_ack,
          nak,
          replacement,
          finished,
          finished_ack
        ] do
      assert {:ok, encoded} = Codec.encode(pdu)
      assert {:ok, decoded} = Codec.decode(encoded)
      assert decoded.payload == pdu.payload
    end
  end

  test "retransmits EOF until the positive ACK limit is reached" do
    assert {:ok, sender} =
             Sender.new(
               source_entity_id: 1,
               transaction_sequence_number: 22,
               destination_entity_id: 3,
               file: <<>>,
               positive_ack_limit: 2
             )

    {sender, [_metadata, eof]} = initial_pdus(sender)
    assert {:ok, retry} = Sender.timer_expired(sender, :positive_ack)
    assert [^eof] = retry.pdus
    assert retry.timers == [{:start, :positive_ack}]

    assert {:ok, fault} = Sender.timer_expired(retry.state, :positive_ack)
    assert fault.state.phase == :faulted
    assert [%{details: %{condition: :positive_ack_limit_reached}}] = fault.indications
  end

  test "responds to acknowledged Prompt PDUs" do
    metadata = incoming(%Metadata{checksum_type: 15, file_size: 4})
    file_data = incoming(%FileData{offset: 0, data: <<1, 2>>})

    assert {:ok, receiver} = Receiver.new(3)
    assert {:ok, with_metadata} = Receiver.ingest(receiver, metadata)
    assert {:ok, with_data} = Receiver.ingest(with_metadata.state, file_data)

    assert {:ok, keep_alive} =
             Receiver.ingest(with_data.state, incoming(%Prompt{response: :keep_alive}))

    assert [%PDU{payload: %KeepAlive{progress: 2}}] = keep_alive.pdus

    assert {:ok, nak} = Receiver.ingest(with_data.state, incoming(%Prompt{response: :nak}))
    assert [%PDU{payload: %NegativeAcknowledgement{}}] = nak.pdus
  end

  test "turns a deferred NAK limit into a Finished fault handshake" do
    metadata = incoming(%Metadata{checksum_type: 15, file_size: 4})
    eof = incoming(%EndOfFile{file_checksum: 0, file_size: 4})

    assert {:ok, receiver} = Receiver.new(3, nak_limit: 1)
    assert {:ok, with_metadata} = Receiver.ingest(receiver, metadata)
    assert {:ok, waiting} = Receiver.ingest(with_metadata.state, eof)
    assert waiting.state.phase == :waiting_repair

    assert {:ok, fault} = Receiver.timer_expired(waiting.state, :nak)
    assert fault.state.phase == :waiting_finished_ack
    assert [%PDU{payload: %Finished{condition: :nak_limit_reached}}] = fault.pdus
    assert fault.timers == [{:cancel, :nak}, {:start, :positive_ack}]
  end

  test "issues immediate and caller-triggered asynchronous NAK sequences" do
    metadata = incoming(%Metadata{checksum_type: 15, file_size: 5})
    out_of_order = incoming(%FileData{offset: 3, data: <<3, 4>>})

    assert {:ok, receiver} = Receiver.new(3, immediate_nak?: true)
    assert {:ok, with_metadata} = Receiver.ingest(receiver, metadata)

    assert {:ok, immediate} = Receiver.ingest(with_metadata.state, out_of_order)

    assert [%PDU{payload: %NegativeAcknowledgement{segment_requests: [{0, 3}]}}] =
             immediate.pdus

    assert immediate.timers == []

    assert {:ok, asynchronous} = Receiver.request_nak(with_metadata.state)

    assert [
             %PDU{
               payload: %NegativeAcknowledgement{
                 start_of_scope: 0,
                 end_of_scope: 0,
                 segment_requests: []
               }
             }
           ] = asynchronous.pdus
  end

  test "suspends and resumes deferred repair without discarding received state" do
    metadata = incoming(%Metadata{checksum_type: 15, file_size: 4})
    eof = incoming(%EndOfFile{file_checksum: 0, file_size: 4})

    assert {:ok, receiver} = Receiver.new(3, nak_limit: 2)
    assert {:ok, with_metadata} = Receiver.ingest(receiver, metadata)
    assert {:ok, waiting} = Receiver.ingest(with_metadata.state, eof)

    assert {:ok, suspended} = Receiver.suspend(waiting.state)
    assert suspended.state.suspended?
    assert suspended.timers == [{:cancel, :nak}]
    assert [%{type: :suspended}] = suspended.indications

    assert {:error, {:transaction_suspended, :nak}} =
             Receiver.timer_expired(suspended.state, :nak)

    assert {:ok, resumed} = Receiver.resume(suspended.state)
    refute resumed.state.suspended?
    assert [%PDU{payload: %NegativeAcknowledgement{}}] = resumed.pdus
    assert resumed.timers == [{:start, :nak}]
    assert [%{type: :resumed, details: %{progress: 0}}] = resumed.indications
  end

  test "applies configurable ignore and suspend handlers to sender faults" do
    ignore_policy = FaultPolicy.new!(handlers: %{positive_ack_limit_reached: :ignore})

    assert {:ok, ignoring_sender} =
             Sender.new(
               source_entity_id: 1,
               transaction_sequence_number: 24,
               destination_entity_id: 3,
               file: <<>>,
               positive_ack_limit: 1,
               fault_policy: ignore_policy
             )

    {ignoring_sender, [_metadata, _eof]} = initial_pdus(ignoring_sender)
    assert {:ok, ignored} = Sender.timer_expired(ignoring_sender, :positive_ack)
    assert ignored.state.phase == :waiting_eof_ack

    assert [%{type: :fault, details: %{condition: :positive_ack_limit_reached}}] =
             ignored.indications

    assert ignored.timers == [{:start, :positive_ack}]

    suspend_policy = FaultPolicy.new!(handlers: %{positive_ack_limit_reached: :suspend})

    assert {:ok, suspending_sender} =
             Sender.new(
               source_entity_id: 1,
               transaction_sequence_number: 25,
               destination_entity_id: 3,
               file: <<>>,
               positive_ack_limit: 1,
               fault_policy: suspend_policy
             )

    {suspending_sender, [_metadata, _eof]} = initial_pdus(suspending_sender)
    assert {:ok, suspended} = Sender.timer_expired(suspending_sender, :positive_ack)
    assert suspended.state.suspended?

    assert [%{type: :suspended, details: %{condition: :positive_ack_limit_reached}}] =
             suspended.indications
  end

  test "completes an acknowledged transfer through an external sink" do
    file = <<1, 2, 3>>
    assert {:ok, checksum} = Checksum.compute(0, file)
    metadata = incoming(%Metadata{checksum_type: 0, file_size: byte_size(file)})
    data = incoming(%FileData{offset: 0, data: file})
    eof = incoming(%EndOfFile{file_checksum: checksum, file_size: byte_size(file)})

    assert {:ok, receiver} = Receiver.new(3, sink: :staging_file)
    assert {:ok, with_metadata} = Receiver.ingest(receiver, metadata)
    assert {:ok, with_data} = Receiver.ingest(with_metadata.state, data)
    assert [%FileEffect{operation: :write, reference: :staging_file}] = with_data.effects

    assert {:ok, verifying} = Receiver.ingest(with_data.state, eof)
    assert verifying.state.phase == :verifying

    assert [
             %PDU{payload: %Acknowledgement{directive: :end_of_file}}
           ] = verifying.pdus

    assert [%FileEffect{operation: :checksum}] = verifying.effects

    assert {:ok, finalizing} = Receiver.checksum_result(verifying.state, {:ok, checksum})
    assert [%FileEffect{operation: :finalize}] = finalizing.effects
    assert {:ok, finished} = Receiver.finalize_result(finalizing.state, :ok)
    assert [%PDU{payload: %Finished{condition: :no_error}}] = finished.pdus
    assert finished.state.phase == :waiting_finished_ack
  end

  test "streams initial and retransmitted Class 2 data from an external source" do
    file = <<0, 1, 2, 3, 4>>
    assert {:ok, checksum} = Checksum.compute(0, file)

    assert {:ok, sender} =
             Sender.new(
               source_entity_id: 1,
               transaction_sequence_number: 26,
               destination_entity_id: 3,
               source: :source_stream,
               file_size: byte_size(file),
               file_checksum: checksum,
               segment_octets: 3
             )

    assert sender.core.file == nil
    assert {:ok, metadata} = Sender.next(sender)
    assert {:ok, first_read} = Sender.next(metadata.state)
    assert [%FileEffect{operation: :read, offset: 0, length: 3}] = first_read.effects
    assert {:ok, first} = Sender.supply_read(first_read.state, <<0, 1, 2>>)
    assert [%PDU{payload: %FileData{offset: 0}}] = first.pdus

    assert {:ok, second_read} = Sender.next(first.state)
    assert [%FileEffect{operation: :read, offset: 3, length: 2}] = second_read.effects
    assert {:ok, second} = Sender.supply_read(second_read.state, <<3, 4>>)
    assert {:ok, eof} = Sender.next(second.state)
    assert eof.state.phase == :waiting_eof_ack

    nak =
      toward_sender(
        26,
        %NegativeAcknowledgement{
          start_of_scope: 0,
          end_of_scope: 3,
          segment_requests: [{0, 3}]
        }
      )

    assert {:ok, retransmission_read} = Sender.ingest(eof.state, nak)

    assert [
             %FileEffect{
               operation: :read,
               reference: :source_stream,
               offset: 0,
               length: 3,
               details: %{retransmission?: true}
             }
           ] = retransmission_read.effects

    assert {:ok, replacement} =
             Sender.supply_read(retransmission_read.state, <<0, 1, 2>>)

    assert [%PDU{payload: %FileData{offset: 0, data: <<0, 1, 2>>}}] = replacement.pdus
    assert replacement.state.phase == :waiting_eof_ack
  end

  defp initial_pdus(sender), do: initial_pdus(sender, [])

  defp initial_pdus(%Sender{phase: :waiting_eof_ack} = sender, pdus),
    do: {sender, Enum.reverse(pdus)}

  defp initial_pdus(sender, pdus) do
    {:ok, transition} = Sender.next(sender)
    initial_pdus(transition.state, Enum.reverse(transition.pdus) ++ pdus)
  end

  defp incoming(payload) do
    %PDU{
      direction: :toward_file_receiver,
      transmission_mode: :acknowledged,
      source_entity_id: 1,
      transaction_sequence_number: 23,
      destination_entity_id: 3,
      entity_id_octets: 1,
      sequence_number_octets: 1,
      payload: payload
    }
  end

  defp toward_sender(sequence_number, payload) do
    %PDU{
      direction: :toward_file_sender,
      transmission_mode: :acknowledged,
      source_entity_id: 1,
      transaction_sequence_number: sequence_number,
      destination_entity_id: 3,
      entity_id_octets: 1,
      sequence_number_octets: 1,
      payload: payload
    }
  end
end
