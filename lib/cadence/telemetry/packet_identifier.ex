defmodule Cadence.Telemetry.PacketIdentifier do
  @moduledoc """
  Fast packet identification using ETS lookup tables.

  For each mission, maintains an ETS table mapping packet identifiers
  (APID, packet type byte, etc.) to packet definitions. This enables
  O(1) identification of incoming packets.

  ## Identification Strategies

  1. **Type Byte** - Single byte packet type (simulator format)
  2. **APID** - CCSDS Application Process Identifier
  3. **Pattern** - First N bytes match pattern
  4. **Custom** - User-defined identification function

  The identifier loads packet definitions from the database on initialization
  and provides fast lookup during packet processing.
  """

  use GenServer
  require Logger

  alias Cadence.Repo
  alias Cadence.Telemetry.Packet

  defmodule State do
    @moduledoc false
    defstruct [
      :mission_id,
      :table_name,
      packets_loaded: 0
    ]
  end

  ## Client API

  @doc """
  Starts the packet identifier for a mission.
  """
  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    GenServer.start_link(__MODULE__, mission_id, name: via_tuple(mission_id))
  end

  @doc """
  Identifies a packet from binary data.

  Returns `{:ok, packet_definition}` or `{:error, :unknown_packet}`.

  ## Identification Process

  1. Extract packet type byte (byte 0 after length header)
  2. Look up in ETS table
  3. Return packet definition with items
  """
  @spec identify(binary(), binary()) ::
          {:ok, map()} | {:error, :unknown_packet}
  def identify(mission_id, binary_packet) when is_binary(binary_packet) do
    table_name = table_name(mission_id)

    # For simulator format: [packet_type:8][target_id_len:8][target_id][json_payload]
    case binary_packet do
      <<packet_type_byte::8, target_id_len::8, rest::binary>> ->
        if byte_size(rest) >= target_id_len do
          <<target_id::binary-size(target_id_len), _payload::binary>> = rest

          case :ets.lookup(table_name, {:type_byte, packet_type_byte}) do
            [{_key, packet_def}] ->
              {:ok, Map.put(packet_def, :target_id, target_id)}

            [] ->
              {:error, :unknown_packet}
          end
        else
          {:error, :malformed_packet}
        end

      _ ->
        {:error, :malformed_packet}
    end
  end

  @doc """
  Identifies a packet using APID (CCSDS standard).
  """
  @spec identify_by_apid(binary(), integer()) ::
          {:ok, map()} | {:error, :unknown_packet}
  def identify_by_apid(mission_id, apid) when is_integer(apid) do
    table_name = table_name(mission_id)

    case :ets.lookup(table_name, {:apid, apid}) do
      [{_key, packet_def}] -> {:ok, packet_def}
      [] -> {:error, :unknown_packet}
    end
  end

  @doc """
  Reloads packet definitions from the database.
  """
  def reload(mission_id) do
    GenServer.call(via_tuple(mission_id), :reload)
  end

  @doc """
  Returns statistics about loaded packets.
  """
  def stats(mission_id) do
    GenServer.call(via_tuple(mission_id), :stats)
  end

  ## Server Callbacks

  @impl true
  def init(mission_id) do
    table_name = table_name(mission_id)

    Logger.info("Creating packet identification table: #{table_name} for mission_id=#{mission_id}")

    # Create ETS table for fast lookups
    _table =
      :ets.new(table_name, [
        :set,
        :named_table,
        :public,
        read_concurrency: true
      ])

    # Subscribe to DefinitionSet change notifications for auto-reload
    alias Cadence.Telemetry.Database.DefinitionSet
    DefinitionSet.subscribe_to_changes(mission_id)

    state = %State{
      mission_id: mission_id,
      table_name: table_name
    }

    # Load packet definitions
    {:ok, load_packet_definitions(state)}
  end

  @impl true
  def handle_call(:reload, _from, state) do
    new_state = load_packet_definitions(state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info({:definition_set_changed, definition_set_id, version}, state) do
    Logger.info(
      "DefinitionSet changed to #{version} (#{definition_set_id}) for mission_id=#{state.mission_id}, reloading packet definitions"
    )

    new_state = load_packet_definitions(state)
    {:noreply, new_state}
  end

  def handle_info(msg, state) do
    Logger.warning("PacketIdentifier received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  def handle_call(:stats, _from, state) do
    stats = %{
      mission_id: state.mission_id,
      packets_loaded: state.packets_loaded,
      table_size: :ets.info(state.table_name, :size)
    }

    {:reply, stats, state}
  end

  @impl true
  def terminate(_reason, state) do
    Logger.info("Terminating packet identifier table: #{state.table_name}")
    :ets.delete(state.table_name)
    :ok
  end

  ## Private Functions

  defp via_tuple(mission_id) do
    {:via, Registry, {Cadence.MissionRegistry, {mission_id, :packet_identifier}}}
  end

  defp table_name(mission_id) when is_binary(mission_id) do
    String.to_atom("packet_id_mission_#{mission_id}")
  end

  defp load_packet_definitions(state) do
    # Clear existing entries
    :ets.delete_all_objects(state.table_name)

    # Load from database
    # For now, we'll use placeholder definitions that match the simulator format
    # In production, this would query the packet_definitions and packet_items tables

    packet_defs = load_from_database(state.mission_id)

    # Insert into ETS
    Enum.each(packet_defs, fn packet_def ->
      # Index by type byte (simulator format)
      if packet_def.type_byte do
        :ets.insert(state.table_name, {{:type_byte, packet_def.type_byte}, packet_def})
      end

      # Index by APID if present (CCSDS format)
      if packet_def.apid do
        Logger.debug("Indexing packet '#{packet_def.name}' by APID=#{packet_def.apid}")
        :ets.insert(state.table_name, {{:apid, packet_def.apid}, packet_def})
      end
    end)

    Logger.info(
      "Loaded #{length(packet_defs)} packet definitions for mission_id=#{state.mission_id}"
    )

    %{state | packets_loaded: length(packet_defs)}
  end

  defp load_from_database(mission_id) do
    import Ecto.Query

    alias Cadence.Telemetry.Database.DefinitionSet

    # First, try to load from the active DefinitionSet (versioned database)
    packet_defs =
      case DefinitionSet.get_active(mission_id) do
        %DefinitionSet{id: definition_set_id} ->
          Logger.info("Loading packet definitions from active DefinitionSet for mission_id=#{mission_id}")

          Packet.PacketDefinition
          |> where([p], p.definition_set_id == ^definition_set_id)
          |> preload(packet_items: [conversion: [:polynomial_conversion, :state_table_conversion, :generic_conversion]])
          |> Repo.all()

        nil ->
          # Fall back to legacy packet definitions (no definition_set_id)
          Logger.info("No active DefinitionSet, loading legacy packet definitions for mission_id=#{mission_id}")

          Packet.PacketDefinition
          |> where([p], p.mission_id == ^mission_id)
          |> where([p], is_nil(p.definition_set_id))
          |> preload(packet_items: [conversion: [:polynomial_conversion, :state_table_conversion, :generic_conversion]])
          |> Repo.all()
      end

    # If no packet definitions found, return empty list
    if Enum.empty?(packet_defs) do
      Logger.warning(
        "No packet definitions found in database for mission_id=#{mission_id}. " <>
        "Import a YAML definition set or create packet definitions to enable telemetry processing."
      )

      []
    else
      # Convert Ecto schemas to maps for ETS storage
      Enum.map(packet_defs, fn packet_def ->
        # Convert packet items to efficient lookup format (with conversions)
        items =
          packet_def.packet_items
          |> Enum.sort_by(& &1.bit_offset)
          |> Enum.map(fn item ->
            %{
              name: item.name,
              bit_offset: item.bit_offset,
              bit_size: item.bit_size,
              data_type: String.to_atom(item.data_type),
              endianness: normalize_endianness(item.endianness),
              description: item.description,
              conversion: item.conversion
            }
          end)

        # Pre-compile field specs for efficient decommutation
        field_specs =
          Enum.map(items, fn item ->
            %{
              name: item.name,
              bit_offset: item.bit_offset,
              bit_size: item.bit_size,
              data_type: item.data_type,
              endianness: item.endianness
            }
          end)

        # Build packet definition map
        %{
          id: packet_def.id,
          mission_id: packet_def.mission_id,
          target_id: nil,  # target_id is set at runtime by the interface, not stored in DB
          name: packet_def.name,
          type_byte: packet_def.type_byte,
          apid: packet_def.apid,
          description: packet_def.description,
          items: items,
          field_specs: field_specs
        }
      end)
    end
  end

  # Normalize endianness strings to atoms expected by BinaryExtractor
  defp normalize_endianness("big"), do: :big_endian
  defp normalize_endianness("little"), do: :little_endian
  defp normalize_endianness("big_endian"), do: :big_endian
  defp normalize_endianness("little_endian"), do: :little_endian
  defp normalize_endianness(nil), do: :big_endian
  defp normalize_endianness(atom) when is_atom(atom), do: atom
end
