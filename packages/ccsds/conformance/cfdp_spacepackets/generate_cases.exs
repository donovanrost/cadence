alias CCSDS.CFDP.{Codec, FileData, PDU}
alias CCSDS.CFDP.Directive.{EndOfFile, Metadata}
alias CCSDS.CFDP.TLV.{FlowLabel, MessageToUser}

emit = fn id, pdu ->
  {:ok, encoded} = Codec.encode(pdu)
  IO.puts(Enum.join(["CASE", id, Base.encode16(encoded)], "\t"))
end

base = fn payload, opts ->
  %PDU{
    direction: Keyword.get(opts, :direction, :toward_file_receiver),
    transmission_mode: Keyword.get(opts, :mode, :unacknowledged),
    crc?: Keyword.get(opts, :crc?, false),
    large_file?: Keyword.get(opts, :large_file?, false),
    source_entity_id: Keyword.get(opts, :source_entity_id, 1),
    transaction_sequence_number: Keyword.get(opts, :sequence_number, 2),
    destination_entity_id: Keyword.get(opts, :destination_entity_id, 3),
    entity_id_octets: Keyword.get(opts, :entity_id_octets, 1),
    sequence_number_octets: Keyword.get(opts, :sequence_number_octets, 1),
    payload: payload
  }
end

for index <- 0..127 do
  supported_widths = [1, 2, 4, 8]
  entity_octets = Enum.at(supported_widths, Integer.mod(index, 4))
  sequence_octets = Enum.at(supported_widths, Integer.mod(index * 3, 4))
  crc? = Integer.mod(index, 2) == 1
  large_file? = Integer.mod(index, 3) == 1
  mode = if(Integer.mod(index, 4) < 2, do: :unacknowledged, else: :acknowledged)
  source = Integer.mod(index * 17 + 1, 250)
  destination = Integer.mod(index * 19 + 3, 250)
  sequence = Integer.mod(index * 23 + 2, 250)

  payload =
    case Integer.mod(index, 3) do
      0 ->
        %Metadata{
          closure_requested?: mode == :unacknowledged and Integer.mod(index, 2) == 0,
          checksum_type: if(Integer.mod(index, 5) == 0, do: 15, else: 0),
          file_size: index * 101,
          source_file_name: "source-#{index}",
          destination_file_name: "destination-#{index}",
          options: [
            %MessageToUser{message: <<index>>},
            %FlowLabel{value: <<Integer.mod(index * 7, 256)>>}
          ]
        }

      1 ->
        offset = if(large_file?, do: 0x1_0000_0000 + index, else: index * 31)
        %FileData{offset: offset, data: <<index, Integer.mod(index * 37, 256)>>}

      2 ->
        size = if(large_file?, do: 0x1_0000_0000 + index, else: index * 43)
        %EndOfFile{file_checksum: index * 65_537, file_size: size}
    end

  pdu =
    base.(payload,
      mode: mode,
      crc?: crc?,
      large_file?: large_file?,
      source_entity_id: source,
      destination_entity_id: destination,
      sequence_number: sequence,
      entity_id_octets: entity_octets,
      sequence_number_octets: sequence_octets
    )

  emit.("ccsds-#{index}", pdu)
end
