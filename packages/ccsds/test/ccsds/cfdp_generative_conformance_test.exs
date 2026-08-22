defmodule CCSDS.CFDP.GenerativeConformanceTest do
  use ExUnit.Case, async: false

  alias CCSDS.CFDP.{Codec, FileData, PDU, Stream}

  alias CCSDS.CFDP.Directive.{
    Acknowledgement,
    EndOfFile,
    Finished,
    KeepAlive,
    Metadata,
    NegativeAcknowledgement,
    Prompt
  }

  alias CCSDS.CFDP.TLV.{FlowLabel, MessageToUser}
  alias CCSDS.TestSupport.DeterministicGenerator, as: Generator

  @seed String.to_integer(System.get_env("CCSDS_GENERATIVE_SEED", "20260720"))
  @cases String.to_integer(System.get_env("CCSDS_GENERATIVE_CASES", "512"))

  @moduletag timeout: 120_000

  test "seeded CFDP PDU fields, CRCs, widths, and streaming boundaries round-trip" do
    {encoded, final_state} =
      Enum.map_reduce(1..@cases, Generator.seed(@seed + 10), fn case_number, state ->
        {pdu, state} = pdu(state, case_number)
        assert {:ok, encoded} = Codec.encode(pdu), "CFDP encode case #{case_number}"
        assert {:ok, decoded} = Codec.decode(encoded), "CFDP decode case #{case_number}"
        assert decoded == pdu, "CFDP semantic round trip case #{case_number}"

        assert {:ok, ^encoded} = Codec.encode(decoded),
               "CFDP exact round trip case #{case_number}"

        {split, state} = Generator.integer(state, 0, byte_size(encoded) - 1)
        <<prefix::binary-size(^split), suffix::binary>> = encoded
        assert {:incomplete, ^prefix} = Codec.decode_prefix(prefix)
        assert {:ok, ^decoded, <<>>} = Codec.decode_prefix(prefix <> suffix)
        {encoded, state}
      end)

    wire = IO.iodata_to_binary(encoded)
    assert {:ok, decoded, <<>>} = Stream.decode(wire)
    assert length(decoded) == @cases
    assert is_tuple(final_state)
  end

  test "arbitrary CFDP input returns a tagged result without raising" do
    final_state =
      Enum.reduce(1..@cases, Generator.seed(@seed + 11), fn case_number, state ->
        {octets, state} = Generator.integer(state, 0, 128)
        {input, state} = Generator.binary(state, octets)
        assert is_tuple(Codec.decode_prefix(input)), "CFDP malformed case #{case_number}"
        state
      end)

    assert is_tuple(final_state)
  end

  defp pdu(state, case_number) do
    {entity_octets, state} = Generator.integer(state, 1, 8)
    {sequence_octets, state} = Generator.integer(state, 1, 8)
    {source_binary, state} = Generator.binary(state, entity_octets)
    {destination_binary, state} = Generator.binary(state, entity_octets)
    {sequence_binary, state} = Generator.binary(state, sequence_octets)
    {crc?, state} = Generator.boolean(state)
    {large_file?, state} = Generator.boolean(state)

    {kind, state} =
      Generator.member(state, [
        :metadata,
        :file_data,
        :end_of_file,
        :finished,
        :acknowledgement,
        :negative_acknowledgement,
        :prompt,
        :keep_alive
      ])

    {payload, direction, mode, record_boundaries?, state} =
      payload(kind, state, large_file?, case_number)

    pdu = %PDU{
      direction: direction,
      transmission_mode: mode,
      crc?: crc?,
      large_file?: large_file?,
      record_boundaries_preserved?: record_boundaries?,
      source_entity_id: :binary.decode_unsigned(source_binary),
      transaction_sequence_number: :binary.decode_unsigned(sequence_binary),
      destination_entity_id: :binary.decode_unsigned(destination_binary),
      entity_id_octets: entity_octets,
      sequence_number_octets: sequence_octets,
      payload: payload
    }

    {pdu, state}
  end

  defp payload(:metadata, state, _large?, _case_number) do
    {mode, state} = Generator.member(state, [:acknowledged, :unacknowledged])
    {closure?, state} = Generator.boolean(state)
    closure? = closure? and mode == :unacknowledged
    {checksum_type, state} = Generator.member(state, [0, 15])
    {file_size, state} = Generator.integer(state, 0, 65_535)
    {source_name, state} = short_binary(state)
    {destination_name, state} = short_binary(state)
    {message, state} = short_binary(state)
    {flow_label, state} = short_binary(state)

    payload = %Metadata{
      closure_requested?: closure?,
      checksum_type: checksum_type,
      file_size: file_size,
      source_file_name: source_name,
      destination_file_name: destination_name,
      options: [%MessageToUser{message: message}, %FlowLabel{value: flow_label}]
    }

    {payload, :toward_file_receiver, mode, false, state}
  end

  defp payload(:file_data, state, large?, case_number) do
    {mode, state} = Generator.member(state, [:acknowledged, :unacknowledged])
    {metadata?, state} = Generator.boolean(state)
    {record_boundaries?, state} = Generator.boolean(state)

    {record_state, state} =
      Generator.member(state, [:no_start_no_end, :start_no_end, :no_start_end, :start_and_end])

    {metadata, state} = if(metadata?, do: short_binary(state), else: {nil, state})
    record_state = if(metadata?, do: record_state, else: :no_start_no_end)
    record_boundaries? = record_boundaries? and metadata?
    {data, state} = short_binary(state)
    {small_offset, state} = Generator.integer(state, 0, 65_535)

    offset =
      if(large? and rem(case_number, 3) == 0,
        do: 0x1_0000_0000 + small_offset,
        else: small_offset
      )

    payload = %FileData{
      offset: offset,
      data: data,
      record_continuation_state: record_state,
      segment_metadata: metadata
    }

    {payload, :toward_file_receiver, mode, record_boundaries?, state}
  end

  defp payload(:end_of_file, state, large?, case_number) do
    {mode, state} = Generator.member(state, [:acknowledged, :unacknowledged])
    {checksum, state} = Generator.integer(state, 0, 0xFFFFFFFF)
    {small_size, state} = Generator.integer(state, 0, 65_535)

    size =
      if(large? and rem(case_number, 5) == 0, do: 0x1_0000_0000 + small_size, else: small_size)

    {%EndOfFile{file_checksum: checksum, file_size: size}, :toward_file_receiver, mode, false,
     state}
  end

  defp payload(:finished, state, _large?, _case_number) do
    {mode, state} = Generator.member(state, [:acknowledged, :unacknowledged])

    {%Finished{condition: :no_error, delivery_code: :complete, file_status: :unreported},
     :toward_file_sender, mode, false, state}
  end

  defp payload(:acknowledgement, state, _large?, _case_number) do
    {directive, state} = Generator.member(state, [:end_of_file, :finished])
    {status, state} = Generator.member(state, [:undefined, :active, :terminated, :unrecognized])

    direction =
      if(directive == :end_of_file, do: :toward_file_sender, else: :toward_file_receiver)

    {%Acknowledgement{directive: directive, transaction_status: status}, direction, :acknowledged,
     false, state}
  end

  defp payload(:negative_acknowledgement, state, _large?, _case_number) do
    {start_offset, state} = Generator.integer(state, 0, 1_000)
    {length, state} = Generator.integer(state, 1, 1_000)
    end_offset = start_offset + length

    {%NegativeAcknowledgement{
       start_of_scope: 0,
       end_of_scope: end_offset,
       segment_requests: [{0, 0}, {start_offset, end_offset}]
     }, :toward_file_sender, :acknowledged, false, state}
  end

  defp payload(:prompt, state, _large?, _case_number) do
    {response, state} = Generator.member(state, [:nak, :keep_alive])
    {%Prompt{response: response}, :toward_file_receiver, :acknowledged, false, state}
  end

  defp payload(:keep_alive, state, large?, case_number) do
    {small_progress, state} = Generator.integer(state, 0, 65_535)

    progress =
      if large? and rem(case_number, 7) == 0,
        do: 0x1_0000_0000 + small_progress,
        else: small_progress

    {%KeepAlive{progress: progress}, :toward_file_sender, :acknowledged, false, state}
  end

  defp short_binary(state) do
    {octets, state} = Generator.integer(state, 0, 32)
    Generator.binary(state, octets)
  end
end
