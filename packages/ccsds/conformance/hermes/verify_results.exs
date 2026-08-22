defmodule CCSDS.Conformance.HermesVerifier do
  alias CCSDS.SDLP.TM.FrameCodec
  alias CCSDS.SpacePacket.Codec, as: SpacePacketCodec
  alias CCSDS.TC.TransferFrame

  @expected_version "v4.0.11"
  @expected_commit "433a8f9fc69a078eb430dab01285d7644e78eb07"

  def run(lines) do
    result =
      Enum.reduce(lines, %{metadata: nil, counts: %{}, binaries: []}, fn line, state ->
        line
        |> String.trim()
        |> String.split("\t")
        |> verify_line(state)
      end)

    assert!(result.metadata != nil, "missing Hermes metadata")
    assert!(result.counts == %{packet: 260, tc: 128, tm: 128}, "unexpected case counts")

    digest =
      result.binaries
      |> Enum.reverse()
      |> IO.iodata_to_binary()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    %{version: version, commit: commit, go: go} = result.metadata

    IO.puts("External interoperability PASS")
    IO.puts("implementation=NASA Hermes")
    IO.puts("version=#{version}")
    IO.puts("commit=#{commit}")
    IO.puts("runtime=#{go}")
    IO.puts("space_packet_cases=#{result.counts.packet}")
    IO.puts("tc_transfer_frame_cases=#{result.counts.tc}")
    IO.puts("tm_transfer_frame_cases=#{result.counts.tm}")
    IO.puts("wire_bytes_sha256=#{digest}")
  end

  defp verify_line(["META", "hermes", version, commit, go], state) do
    assert!(version == @expected_version, "unexpected Hermes version #{version}")
    assert!(commit == @expected_commit, "unexpected Hermes commit #{commit}")
    %{state | metadata: %{version: version, commit: commit, go: go}}
  end

  defp verify_line(
         ["RESULT", "PACKET", _id, type, secondary, apid, flag, count, data_hex, wire_hex],
         state
       ) do
    wire = hex!(wire_hex)
    data = hex!(data_hex)

    packet = expect_ok(SpacePacketCodec.decode(wire), "CCSDS rejected Hermes packet")
    assert!(packet.packet_type == String.to_existing_atom(type), "packet type mismatch")
    assert!(packet.secondary_header? == (secondary == "1"), "secondary-header mismatch")
    assert!(packet.apid == integer!(apid), "APID mismatch")
    assert!(packet.sequence_flag == String.to_existing_atom(flag), "sequence flag mismatch")
    assert!(packet.sequence_count == integer!(count), "sequence count mismatch")
    assert!(packet.data == data, "packet data mismatch")
    accumulate(state, :packet, wire)
  end

  defp verify_line(
         ["RESULT", "TC", _id, scid, vcid, frame_sequence, payload_hex, wire_hex],
         state
       ) do
    wire = hex!(wire_hex)
    payload = hex!(payload_hex)

    frame =
      expect_single(
        TransferFrame.decode(wire, frame_size: 1024, fecf: true),
        "CCSDS rejected Hermes TC frame"
      )

    assert!(frame.bypass_flag == 1, "TC bypass flag mismatch")
    assert!(frame.control_command_flag == 0, "TC control-command flag mismatch")
    assert!(frame.scid == integer!(scid), "TC SCID mismatch")
    assert!(frame.vcid == integer!(vcid), "TC VCID mismatch")
    assert!(frame.frame_seq == integer!(frame_sequence), "TC frame sequence mismatch")
    assert!(frame.payload == payload, "TC payload mismatch")
    assert!(is_integer(frame.fecf), "TC FECF missing")
    accumulate(state, :tc, wire)
  end

  defp verify_line(
         [
           "RESULT",
           "TM",
           _id,
           scid,
           vcid,
           mcfc,
           vcfc,
           sync_flag,
           packet_order_flag,
           segment_length_id,
           fhp,
           secondary_hex,
           payload_hex,
           wire_hex
         ],
         state
       ) do
    wire = hex!(wire_hex)
    payload = hex!(payload_hex)
    secondary_data = optional_hex!(secondary_hex)
    secondary_header_length = if secondary_data == nil, do: 0, else: byte_size(secondary_data) + 1

    frame =
      expect_single(
        FrameCodec.decode(wire,
          frame_size: byte_size(wire),
          secondary_header_length: secondary_header_length
        ),
        "CCSDS rejected Hermes TM frame"
      )

    assert!(frame.scid == integer!(scid), "TM SCID mismatch")
    assert!(frame.vcid == integer!(vcid), "TM VCID mismatch")
    assert!(frame.meta.mcfc == integer!(mcfc), "TM MCFC mismatch")
    assert!(frame.meta.vcfc == integer!(vcfc), "TM VCFC mismatch")
    assert!(frame.meta.sync_flag == integer!(sync_flag), "TM sync flag mismatch")

    assert!(
      frame.meta.packet_order_flag == integer!(packet_order_flag),
      "TM packet-order flag mismatch"
    )

    assert!(
      frame.meta.segment_length_id == integer!(segment_length_id),
      "TM segment-length ID mismatch"
    )

    assert!(frame.meta.fhp == integer!(fhp), "TM FHP mismatch")
    assert!(frame.payload_octets == payload, "TM payload mismatch")

    case secondary_data do
      nil ->
        assert!(!Map.has_key?(frame.meta, :secondary_header), "unexpected TM secondary header")

      data ->
        assert!(frame.meta.secondary_header_data == data, "TM secondary header mismatch")
    end

    accumulate(state, :tm, wire)
  end

  defp verify_line(fields, _state), do: raise("unexpected Hermes result #{inspect(fields)}")

  defp accumulate(state, type, wire) do
    count = Map.get(state.counts, type, 0)
    %{state | counts: Map.put(state.counts, type, count + 1), binaries: [wire | state.binaries]}
  end

  defp hex!(value) do
    case Base.decode16(value, case: :mixed) do
      {:ok, binary} -> binary
      :error -> raise("invalid hex #{inspect(value)}")
    end
  end

  defp optional_hex!("-"), do: nil
  defp optional_hex!(value), do: hex!(value)

  defp integer!(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _other -> raise("invalid integer #{inspect(value)}")
    end
  end

  defp expect_ok({:ok, value}, _message), do: value
  defp expect_ok(result, message), do: raise("#{message}: #{inspect(result)}")

  defp expect_single({:ok, [value], <<>>}, _message), do: value
  defp expect_single(result, message), do: raise("#{message}: #{inspect(result)}")

  defp assert!(true, _message), do: :ok
  defp assert!(false, message), do: raise(message)
end

CCSDS.Conformance.HermesVerifier.run(IO.stream(:stdio, :line))
