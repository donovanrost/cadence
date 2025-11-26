defmodule Cadence.Telemetry.Packet do
  @moduledoc """
  Universal packet structure that normalizes different telemetry formats.

  Packets progress through stages:
  - **Delineated**: Raw packet extracted from stream by protocol chain
  - **Identified**: Packet definition matched via PacketIdentifier
  - **Processed**: Telemetry items extracted and converted

  Format-specific headers (like CCSDS) are stored in optional fields.
  After processing, all packets converge to a common shape with items map.

  ## Examples

      # CCSDS packet from spacecraft
      {:ok, packet} = Packet.from_ccsds(ccsds_binary, metadata)
      packet.ccsds_header.apid
      #=> 100

      # Simulator packet
      packet = Packet.from_simulator(sim_binary, metadata)
      packet.ccsds_header
      #=> nil

      # Extract payload for decommutation
      {:ok, payload} = Packet.get_payload(packet)
  """

  defstruct [
    # Core Identity
    :mission_id,
    :target_id,
    :packet_name,

    # Timing
    :received_time,
    :packet_time,

    # Binary Data
    :raw,  # Original packet bytes

    # Format-Specific Headers (optional)
    :ccsds_header,  # CCSDSHeader struct or nil

    # Packet Definition (after identification)
    :definition,

    # Processed Items (after decommutation)
    items: %{},

    # Quality & Limits (after limit checking)
    limits: %{},
    quality: :good,

    # Metadata
    stored: false,
    interface_id: nil,
    source: %{}
  ]

  defmodule CCSDSHeader do
    @moduledoc """
    CCSDS Space Packet primary and secondary header fields.

    ## Primary Header (6 bytes)
    Standard CCSDS Space Packet Protocol header containing packet identification
    and sequence information.

    ## Secondary Header (8 bytes, mission-specific)
    Custom secondary header with timestamp and target identifier.
    """
    defstruct [
      # Primary Header (6 bytes)
      :apid,              # 11-bit Application Process ID
      :sequence_count,    # 14-bit sequence number
      :sequence_flags,    # 2-bit flags (0=continuation, 1=first, 2=last, 3=standalone)
      :packet_length,     # 16-bit data length (excludes primary header)
      :version,           # 3-bit version (always 0 for space packets)
      :type,              # 1-bit type (0=telemetry, 1=command)
      :secondary_header_flag,  # 1-bit flag

      # Secondary Header (8 bytes, mission-specific)
      :timestamp,         # 6-byte mission time (CCSDS day segmented time code)
      :target_hash        # 2-byte target identifier hash
    ]
  end

  ## Constructor Functions

  @doc """
  Creates a Packet from CCSDS format binary data.

  Parses the CCSDS primary and secondary headers, stores the complete
  packet in the :raw field.

  ## Examples

      metadata = %{
        mission_id: "abc-123",
        target_id: "SAT-1",
        received_at: DateTime.utc_now(),
        interface_id: "if-1"
      }

      {:ok, packet} = Packet.from_ccsds(ccsds_binary, metadata)
      packet.ccsds_header.apid
      #=> 100
  """
  def from_ccsds(binary, metadata \\ %{}) when is_binary(binary) do
    case parse_ccsds_header(binary) do
      {:ok, ccsds_header} ->
        {:ok,
         %__MODULE__{
           mission_id: metadata[:mission_id],
           target_id: metadata[:target_id],
           received_time: metadata[:received_at] || DateTime.utc_now(),
           raw: binary,
           ccsds_header: ccsds_header,
           packet_time: ccsds_header.timestamp,
           stored: metadata[:stored] || false,
           interface_id: metadata[:interface_id],
           source: metadata
         }}

      {:error, _reason} = error ->
        error
    end
  end

  @doc """
  Creates a Packet from simulator format binary data.

  Simulator format: `[type:8][target_id_len:8][target_id][JSON]`

  ## Examples

      metadata = %{
        mission_id: "abc-123",
        target_id: "SIM-1"
      }

      packet = Packet.from_simulator(sim_binary, metadata)
      packet.ccsds_header
      #=> nil
  """
  def from_simulator(binary, metadata \\ %{}) when is_binary(binary) do
    %__MODULE__{
      mission_id: metadata[:mission_id],
      target_id: metadata[:target_id],
      received_time: metadata[:received_at] || DateTime.utc_now(),
      raw: binary,
      ccsds_header: nil,  # No CCSDS header for simulator packets
      stored: metadata[:stored] || false,
      interface_id: metadata[:interface_id],
      source: metadata
    }
  end

  ## Header Parsing

  @doc """
  Parses CCSDS primary and secondary headers from binary data.

  Returns `{:ok, %CCSDSHeader{}}` or `{:error, reason}`.

  ## CCSDS Primary Header (6 bytes)

  - Bits 0-2: Version (3 bits)
  - Bit 3: Type (1 bit)
  - Bit 4: Secondary Header Flag (1 bit)
  - Bits 5-15: APID (11 bits)
  - Bits 16-17: Sequence Flags (2 bits)
  - Bits 18-31: Sequence Count (14 bits)
  - Bits 32-47: Packet Length (16 bits)

  ## Mission Secondary Header (8 bytes)

  - Bytes 0-5: Timestamp (6 bytes, CCSDS day segmented time code)
  - Bytes 6-7: Target Hash (2 bytes)

  ## Examples

      {:ok, header} = Packet.parse_ccsds_header(ccsds_binary)
      header.apid
      #=> 100
  """
  def parse_ccsds_header(binary) when byte_size(binary) >= 14 do
    # Parse primary header (6 bytes)
    <<
      version::3,
      type::1,
      secondary_header_flag::1,
      apid::11,
      sequence_flags::2,
      sequence_count::14,
      packet_length::16,
      rest::binary
    >> = binary

    # Parse secondary header (8 bytes) if present
    if secondary_header_flag == 1 and byte_size(rest) >= 8 do
      <<timestamp_bytes::binary-size(6), target_hash::16, _payload::binary>> = rest

      # Convert timestamp bytes to DateTime
      timestamp = parse_ccsds_timestamp(timestamp_bytes)

      {:ok,
       %CCSDSHeader{
         version: version,
         type: type,
         secondary_header_flag: secondary_header_flag,
         apid: apid,
         sequence_flags: sequence_flags,
         sequence_count: sequence_count,
         packet_length: packet_length,
         timestamp: timestamp,
         target_hash: target_hash
       }}
    else
      {:error, :missing_secondary_header}
    end
  end

  def parse_ccsds_header(_binary), do: {:error, :insufficient_data}

  ## Helper Functions

  @doc """
  Returns the packet format (`:ccsds` or `:simulator`).

  ## Examples

      Packet.get_format(ccsds_packet)
      #=> :ccsds

      Packet.get_format(sim_packet)
      #=> :simulator
  """
  def get_format(%__MODULE__{ccsds_header: nil}), do: :simulator
  def get_format(%__MODULE__{ccsds_header: %CCSDSHeader{}}), do: :ccsds

  @doc """
  Extracts the APID from a CCSDS packet, or nil for simulator packets.

  ## Examples

      Packet.get_apid(ccsds_packet)
      #=> 100

      Packet.get_apid(sim_packet)
      #=> nil
  """
  def get_apid(%__MODULE__{ccsds_header: %CCSDSHeader{apid: apid}}), do: apid
  def get_apid(%__MODULE__{ccsds_header: nil}), do: nil

  @doc """
  Extracts the target_id from the packet.

  ## Examples

      Packet.get_target_id(packet)
      #=> "SAT-1"
  """
  def get_target_id(%__MODULE__{target_id: target_id}), do: target_id

  @doc """
  Extracts the payload from the packet based on format.

  For CCSDS: Skips primary header (6 bytes) + secondary header (8 bytes)
  For simulator: Skips type byte + target_id_len + target_id

  ## Examples

      {:ok, payload} = Packet.get_payload(packet)
  """
  def get_payload(%__MODULE__{raw: raw, ccsds_header: %CCSDSHeader{}}) do
    # Skip 6-byte primary header + 8-byte secondary header = 14 bytes
    case raw do
      <<_header::binary-size(14), payload::binary>> -> {:ok, payload}
      _ -> {:error, :invalid_packet_size}
    end
  end

  def get_payload(%__MODULE__{raw: raw, ccsds_header: nil}) do
    # Simulator format: [type:8][target_id_len:8][target_id][payload]
    case raw do
      <<_type::8, target_id_len::8, rest::binary>> ->
        if byte_size(rest) >= target_id_len do
          <<_target_id::binary-size(target_id_len), payload::binary>> = rest
          {:ok, payload}
        else
          {:error, :malformed_packet}
        end

      _ ->
        {:error, :invalid_packet_structure}
    end
  end

  @doc """
  Extracts the packet type byte from simulator format packets.

  Returns `{:ok, type_byte}` or `{:error, reason}`.

  ## Examples

      {:ok, type_byte} = Packet.get_type_byte(sim_packet)
      #=> {:ok, 1}

      Packet.get_type_byte(ccsds_packet)
      #=> {:error, :not_simulator_format}
  """
  def get_type_byte(%__MODULE__{raw: raw, ccsds_header: nil}) do
    case raw do
      <<type_byte::8, _rest::binary>> -> {:ok, type_byte}
      _ -> {:error, :invalid_packet_structure}
    end
  end

  def get_type_byte(%__MODULE__{ccsds_header: %CCSDSHeader{}}),
    do: {:error, :not_simulator_format}

  @doc """
  Adds a decoded item to the packet.
  """
  def put_item(%__MODULE__{} = packet, item_name, value) do
    %{packet | items: Map.put(packet.items, item_name, value)}
  end

  @doc """
  Gets a decoded item from the packet.
  """
  def get_item(%__MODULE__{items: items}, item_name) do
    Map.get(items, item_name)
  end

  ## Private Functions

  # Parse CCSDS day segmented time code (6 bytes)
  # Format: [day_since_epoch:16][ms_of_day:32]
  defp parse_ccsds_timestamp(<<days::16, ms_of_day::32>>) do
    # CCSDS epoch: 1958-01-01
    epoch = ~U[1958-01-01 00:00:00Z]

    # Calculate DateTime
    # Add days as seconds, then add milliseconds
    DateTime.add(epoch, days * 86400 + div(ms_of_day, 1000), :second)
  end

  defp parse_ccsds_timestamp(_), do: nil
end
