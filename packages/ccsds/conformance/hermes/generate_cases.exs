alias CCSDS.Core.LinkFrame
alias CCSDS.SDLP.TM.{FrameCodec, SecondaryHeader}
alias CCSDS.SpacePacket
alias CCSDS.SpacePacket.Codec, as: SpacePacketCodec
alias CCSDS.TC.TransferFrame

hex = &Base.encode16/1

data_for = fn index, length ->
  0..(length - 1)
  |> Enum.map(&Integer.mod(index * 73 + &1 * 37 + 11, 256))
  |> :binary.list_to_bin()
end

packet_cases = [
  {:telemetry, false, 0, :continuation, 0, <<0>>},
  {:telemetry, true, 1, :first, 1, <<1, 2>>},
  {:command, false, 0x7FE, :last, 0x3FFE, <<0xFE>>},
  {:command, false, 0x7FF, :unsegmented, 0x3FFF, <<0xFF, 0>>}
]

packet_cases =
  packet_cases ++
    for index <- 0..255 do
      apid = Integer.mod(index * 811 + 17, 2048)
      data_length = Integer.mod(index * 29, 128) + 1

      {
        if(Integer.mod(index, 2) == 0, do: :telemetry, else: :command),
        Integer.mod(div(index, 2), 2) == 1 and apid != SpacePacket.idle_apid(),
        apid,
        Enum.at([:continuation, :first, :last, :unsegmented], Integer.mod(index, 4)),
        Integer.mod(index * 4051 + 97, 16_384),
        data_for.(index, data_length)
      }
    end

packet_cases
|> Enum.with_index()
|> Enum.each(fn {{packet_type, secondary_header?, apid, sequence_flag, sequence_count, data},
                 index} ->
  packet =
    SpacePacket.new(%{
      packet_type: packet_type,
      secondary_header?: secondary_header?,
      apid: apid,
      sequence_flag: sequence_flag,
      sequence_count: sequence_count,
      data: data
    })

  {:ok, encoded} = SpacePacketCodec.encode(packet)

  IO.puts(
    Enum.join(
      [
        "PACKET",
        "packet-#{index}",
        packet_type,
        if(secondary_header?, do: 1, else: 0),
        apid,
        sequence_flag,
        sequence_count,
        hex.(data),
        hex.(encoded)
      ],
      "\t"
    )
  )
end)

for index <- 0..127 do
  scid = Integer.mod(index * 313 + 7, 1024)
  vcid = Integer.mod(index * 23 + 3, 64)
  frame_seq = Integer.mod(index * 197 + 5, 256)
  payload = data_for.(index + 300, Integer.mod(index * 31, 128) + 1)

  frame = %TransferFrame{
    version: 0,
    bypass_flag: 1,
    control_command_flag: 0,
    spare: 0,
    scid: scid,
    vcid: vcid,
    frame_seq: frame_seq,
    payload: payload
  }

  {:ok, encoded} = TransferFrame.encode(frame, frame_size: 1024, fecf: true)

  IO.puts(
    Enum.join(
      ["TC", "tc-#{index}", scid, vcid, frame_seq, hex.(payload), hex.(encoded)],
      "\t"
    )
  )
end

for index <- 0..127 do
  scid = Integer.mod(index * 419 + 13, 1024)
  vcid = Integer.mod(index * 5 + 1, 8)
  mcfc = Integer.mod(index * 193 + 9, 256)
  vcfc = Integer.mod(index * 181 + 7, 256)
  vca? = Integer.mod(index, 2) == 1
  secondary? = Integer.mod(index, 3) == 1
  payload = data_for.(index + 600, Integer.mod(index * 17, 128) + 1)

  secondary_data =
    if secondary?, do: data_for.(index + 900, Integer.mod(index, 8) + 1), else: <<>>

  secondary_header =
    if secondary? do
      {:ok, header} = SecondaryHeader.new(secondary_data)
      header
    end

  {sync_flag, packet_order_flag, segment_length_id, fhp} =
    if vca? do
      {1, Integer.mod(index, 2), Integer.mod(index, 4), Integer.mod(index * 97, 2048)}
    else
      {0, 0, 3, Integer.mod(index * 97, 2048)}
    end

  secondary_header_length = if secondary?, do: byte_size(secondary_data) + 1, else: 0
  frame_size = 6 + secondary_header_length + byte_size(payload)

  frame = %LinkFrame{
    profile: :tm,
    scid: scid,
    vcid: vcid,
    frame_seq: vcfc,
    payload_octets: payload,
    quality: :good,
    meta: %{
      mcfc: mcfc,
      vcfc: vcfc,
      sync_flag: sync_flag,
      packet_order_flag: packet_order_flag,
      segment_length_id: segment_length_id,
      fhp: fhp,
      secondary_header: secondary_header
    }
  }

  {:ok, encoded} =
    FrameCodec.encode(frame,
      frame_size: frame_size,
      secondary_header_length: secondary_header_length
    )

  IO.puts(
    Enum.join(
      [
        "TM",
        "tm-#{index}",
        scid,
        vcid,
        mcfc,
        vcfc,
        sync_flag,
        packet_order_flag,
        segment_length_id,
        fhp,
        if(secondary?, do: hex.(secondary_data), else: "-"),
        hex.(payload),
        hex.(encoded)
      ],
      "\t"
    )
  )
end
