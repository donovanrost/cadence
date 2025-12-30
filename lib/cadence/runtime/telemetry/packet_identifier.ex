defmodule Cadence.Runtime.Telemetry.PacketIdentifier do
  @moduledoc """
  Fast packet identification using ETS lookup tables.

  For each mission, maintains an ETS table mapping packet identifiers
  (APID, packet type byte, etc.) to packet definitions. This enables
  O(1) identification of incoming packets.

  ## Target-Scoped Definition Sets

  Different targets within a mission can use different dictionaries (DefinitionSets).
  At startup, the identifier pre-loads packet definitions for all definition_sets
  used by targets in the mission. Lookups are keyed by `{definition_set_id, apid}`.

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

  import Ecto.Query

  alias Cadence.Config.VersionRegistry
  alias Cadence.MissionDatabase.Container
  alias Cadence.Repo

  defmodule State do
    @moduledoc false
    defstruct [
      :mission_id,
      :table_name,
      packets_loaded: 0,
      definition_sets_loaded: [],
      # Track version per definition_set for cache invalidation
      definition_set_versions: %{}
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

  Uses cached target → definition_set_id mapping for O(1) lookup.
  Targets must have a definition_set_id assigned.

  ## Identification Process

  1. Extract packet type byte (byte 0 after length header)
  2. Look up cached definition_set_id for the target
  3. Look up packet definition in ETS table
  4. Return packet definition with items
  """
  @spec identify(binary(), binary()) ::
          {:ok, map()} | {:error, :unknown_packet | :malformed_packet}
  def identify(mission_id, binary_packet) when is_binary(binary_packet) do
    table_name = table_name(mission_id)

    # For simulator format: [packet_type:8][target_id_len:8][target_id][json_payload]
    with {:ok, packet_type_byte, target_id} <- decode_simulator_packet(binary_packet),
         definition_set_id <- get_cached_definition_set_id(table_name, mission_id, target_id),
         {:ok, packet_def} <- lookup_by_type_byte(table_name, definition_set_id, packet_type_byte) do
      {:ok, Map.put(packet_def, :target_id, target_id)}
    else
      :not_found -> {:error, :unknown_packet}
      {:error, :malformed_packet} -> {:error, :malformed_packet}
    end
  end

  @doc """
  Identifies a packet for a specific target using its database.

  Uses cached target → definition_set_id mapping for O(1) lookup.
  """
  @spec identify_for_target(binary(), binary(), binary()) ::
          {:ok, map()} | {:error, :unknown_packet | :malformed_packet}
  def identify_for_target(mission_id, target_identifier, binary_packet)
      when is_binary(binary_packet) do
    table_name = table_name(mission_id)
    definition_set_id = get_cached_definition_set_id(table_name, mission_id, target_identifier)

    # For simulator format: [packet_type:8][target_id_len:8][target_id][json_payload]
    with {:ok, packet_type_byte, target_id} <- decode_simulator_packet(binary_packet),
         {:ok, packet_def} <- lookup_by_type_byte(table_name, definition_set_id, packet_type_byte) do
      {:ok, Map.put(packet_def, :target_id, target_id)}
    else
      :not_found -> {:error, :unknown_packet}
      {:error, :malformed_packet} -> {:error, :malformed_packet}
    end
  end

  @doc """
  Identifies a packet using APID (CCSDS standard) for a specific target.

  Uses cached target → definition_set_id mapping for O(1) lookup.
  """
  @spec identify_by_apid(binary(), binary(), integer()) ::
          {:ok, map()} | {:error, :unknown_packet}
  def identify_by_apid(mission_id, target_identifier, apid) when is_integer(apid) do
    table_name = table_name(mission_id)

    # Look up cached definition_set_id for this target (O(1) ETS lookup)
    definition_set_id = get_cached_definition_set_id(table_name, mission_id, target_identifier)

    case :ets.lookup(table_name, {definition_set_id, :apid, apid}) do
      [{_key, packet_def}] -> {:ok, packet_def}
      [] -> {:error, :unknown_packet}
    end
  end

  # Get cached definition_set_id for a target
  # Target must have a definition_set_id assigned (no fallback)
  defp get_cached_definition_set_id(table_name, _mission_id, target_identifier) do
    case :ets.lookup(table_name, {:target_ds, target_identifier}) do
      [{_key, definition_set_id}] ->
        definition_set_id

      [] ->
        # Target not in cache - this means target has no definition_set_id
        Logger.warning("No definition_set_id cached for target #{target_identifier}")
        nil
    end
  end

  @doc """
  Looks up a target's UUID by its identifier.

  Returns `{:ok, target_id}` or `{:error, :not_found}`.
  O(1) ETS lookup - no database call.

  ## Example

      {:ok, uuid} = PacketIdentifier.get_target_id(mission_id, "SAT-001")

  """
  @spec get_target_id(String.t(), String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def get_target_id(mission_id, identifier) do
    table = table_name(mission_id)

    case :ets.lookup(table, {:target_id, identifier}) do
      [{_key, target_id}] -> {:ok, target_id}
      [] -> {:error, :not_found}
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

    Logger.info(
      "Creating packet identification table: #{table_name} for mission_id=#{mission_id}"
    )

    # Create ETS table for fast lookups
    _table =
      :ets.new(table_name, [
        :set,
        :named_table,
        :public,
        read_concurrency: true
      ])

    # Subscribe to change notifications for auto-reload
    Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:definition_set")
    Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:targets")

    state = %State{
      mission_id: mission_id,
      table_name: table_name
    }

    # Load packet definitions for all definition_sets used by mission targets
    state = load_all_definition_sets(state)

    # Subscribe to version invalidation for each loaded definition_set
    Enum.each(state.definition_sets_loaded, fn ds_id ->
      Phoenix.PubSub.subscribe(
        Cadence.PubSub,
        VersionRegistry.topic_for(:definition_set, ds_id)
      )
    end)

    {:ok, state}
  end

  @impl true
  def handle_call(:reload, _from, state) do
    new_state = load_all_definition_sets(state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      mission_id: state.mission_id,
      packets_loaded: state.packets_loaded,
      definition_sets_loaded: length(state.definition_sets_loaded),
      table_size: :ets.info(state.table_name, :size)
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_info({:definition_set_changed, definition_set_id, version}, state) do
    Logger.info(
      "DefinitionSet changed to #{version} (#{definition_set_id}) for mission_id=#{state.mission_id}, reloading packet definitions"
    )

    new_state = load_all_definition_sets(state)
    {:noreply, new_state}
  end

  def handle_info({:target_definition_set_changed, target_id, definition_set_id}, state) do
    Logger.info(
      "Target #{target_id} changed to definition_set #{definition_set_id}, reloading packet definitions"
    )

    new_state = load_all_definition_sets(state)
    {:noreply, new_state}
  end

  # Handle generic target update events (created, updated, deleted)
  def handle_info({:target_updated, _target}, state) do
    Logger.debug("Target updated, refreshing target definition_set cache")
    cache_target_definition_sets(state.table_name, state.mission_id)
    {:noreply, state}
  end

  def handle_info({:target_created, _target}, state) do
    Logger.debug("Target created, refreshing target definition_set cache")
    cache_target_definition_sets(state.table_name, state.mission_id)
    {:noreply, state}
  end

  def handle_info({:target_deleted, _target}, state) do
    Logger.debug("Target deleted, refreshing target definition_set cache")
    cache_target_definition_sets(state.table_name, state.mission_id)
    {:noreply, state}
  end

  # Handle version invalidation from VersionRegistry
  def handle_info({:config_invalidated, :definition_set, definition_set_id, new_version}, state) do
    current_version = Map.get(state.definition_set_versions, definition_set_id, 0)

    if new_version > current_version do
      Logger.info(
        "Config version changed for definition_set=#{definition_set_id} " <>
          "(#{current_version} -> #{new_version}), reloading PacketIdentifier"
      )

      # Reload just this definition_set's packets
      count = load_for_definition_set(state.table_name, definition_set_id)

      new_versions = Map.put(state.definition_set_versions, definition_set_id, new_version)

      Logger.info("Reloaded #{count} packets for definition_set=#{definition_set_id}")

      {:noreply, %{state | definition_set_versions: new_versions}}
    else
      {:noreply, state}
    end
  end

  def handle_info(msg, state) do
    Logger.warning("PacketIdentifier received unexpected message: #{inspect(msg)}")
    {:noreply, state}
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

  # Look up by type byte, scoped by definition_set_id
  defp lookup_by_type_byte(table_name, definition_set_id, type_byte) do
    case :ets.lookup(table_name, {definition_set_id, :type_byte, type_byte}) do
      [{_key, packet_def}] -> {:ok, packet_def}
      [] -> :not_found
    end
  end

  # Load packet definitions for all definition_sets used by mission targets
  defp load_all_definition_sets(state) do
    # Clear existing entries
    :ets.delete_all_objects(state.table_name)

    # Cache target → definition_set_id mappings for O(1) lookup during packet processing
    cache_target_definition_sets(state.table_name, state.mission_id)

    # Get all unique definition_set_ids used by targets in this mission
    definition_set_ids = get_mission_definition_set_ids(state.mission_id)

    Logger.info(
      "Loading packet definitions for #{length(definition_set_ids)} definition_sets in mission_id=#{state.mission_id}"
    )

    # Load packet definitions for each definition_set and track versions
    {total_packets, versions} =
      Enum.reduce(definition_set_ids, {0, %{}}, fn definition_set_id, {acc, vers} ->
        count = load_for_definition_set(state.table_name, definition_set_id)
        version = VersionRegistry.get_version(:definition_set, definition_set_id)
        {acc + count, Map.put(vers, definition_set_id, version)}
      end)

    Logger.info(
      "Loaded #{total_packets} packets from #{length(definition_set_ids)} definition_sets for mission_id=#{state.mission_id}"
    )

    %{
      state
      | packets_loaded: total_packets,
        definition_sets_loaded: definition_set_ids,
        definition_set_versions: versions
    }
  end

  # Cache target identifier → definition_set_id and identifier → target_id mappings in ETS
  # This avoids DB queries during packet processing and rule filtering
  # Note: Targets must have a definition_set_id assigned (required field)
  defp cache_target_definition_sets(table_name, mission_id) do
    # Get all targets with their id, identifier, and definition_set_id
    targets =
      Cadence.Targets.Target
      |> where([t], t.mission_id == ^mission_id)
      |> where([t], not is_nil(t.definition_set_id))
      |> select([t], {t.id, t.identifier, t.definition_set_id})
      |> Repo.all()

    # Cache each target's definition_set_id and target UUID
    Enum.each(targets, fn {target_id, identifier, ds_id} ->
      # For definition_set lookup (used by packet identification)
      :ets.insert(table_name, {{:target_ds, identifier}, ds_id})

      # For target UUID lookup (used by RuleCache, etc.)
      :ets.insert(table_name, {{:target_id, identifier}, target_id})
    end)

    Logger.debug(
      "Cached #{length(targets)} target mappings (identifier → definition_set_id, UUID) " <>
        "for mission_id=#{mission_id}"
    )
  end

  # Gets all unique definition_set_ids used by targets in this mission
  defp get_mission_definition_set_ids(mission_id) do
    # Get all unique definition_set_ids from targets
    Cadence.Targets.Target
    |> where([t], t.mission_id == ^mission_id)
    |> where([t], not is_nil(t.definition_set_id))
    |> select([t], t.definition_set_id)
    |> distinct(true)
    |> Repo.all()
  end

  # Load packet definitions for a specific definition_set
  # Uses the new MissionDatabase Container model
  defp load_for_definition_set(table_name, definition_set_id) do
    # Query containers (packets) from the MissionDatabase model
    containers =
      Container
      |> where([c], c.definition_set_id == ^definition_set_id)
      |> where([c], c.abstract == false or is_nil(c.abstract))
      |> preload(container_entries: [parameter: [data_type: [:default_calibrator, :unit]]])
      |> Repo.all()

    case containers do
      [] ->
        Logger.debug("No containers found for definition_set_id=#{definition_set_id}")
        0

      _ ->
        Enum.each(containers, fn container ->
          insert_container_packet(table_name, definition_set_id, container)
        end)

        length(containers)
    end
  end

  defp decode_simulator_packet(<<packet_type_byte::8, target_id_len::8, rest::binary>>) do
    if byte_size(rest) >= target_id_len do
      <<target_id::binary-size(target_id_len), _payload::binary>> = rest
      {:ok, packet_type_byte, target_id}
    else
      {:error, :malformed_packet}
    end
  end

  defp decode_simulator_packet(_), do: {:error, :malformed_packet}

  defp insert_container_packet(table_name, definition_set_id, container) do
    packet_map = build_packet_map_from_container(container, definition_set_id)
    maybe_insert_packet_type(table_name, definition_set_id, container, packet_map)
    maybe_insert_packet_apid(table_name, definition_set_id, container, packet_map)
  end

  defp maybe_insert_packet_type(
         _table_name,
         _definition_set_id,
         %{packet_type: nil},
         _packet_map
       ),
       do: :ok

  defp maybe_insert_packet_type(table_name, definition_set_id, container, packet_map) do
    :ets.insert(
      table_name,
      {{definition_set_id, :type_byte, container.packet_type}, packet_map}
    )
  end

  defp maybe_insert_packet_apid(_table_name, _definition_set_id, %{apid: nil}, _packet_map),
    do: :ok

  defp maybe_insert_packet_apid(table_name, definition_set_id, container, packet_map) do
    :ets.insert(table_name, {{definition_set_id, :apid, container.apid}, packet_map})
  end

  # Normalize endianness strings to atoms expected by BinaryExtractor
  defp normalize_endianness("big"), do: :big_endian
  defp normalize_endianness("little"), do: :little_endian
  defp normalize_endianness("big_endian"), do: :big_endian
  defp normalize_endianness("little_endian"), do: :little_endian
  defp normalize_endianness(nil), do: :big_endian
  defp normalize_endianness(atom) when is_atom(atom), do: atom

  # Build packet definition map from MissionDatabase Container model
  defp build_packet_map_from_container(container, definition_set_id) do
    # Convert container entries to packet items format
    # Only include parameter_ref entries (not fixed_value, container_ref, etc.)
    items =
      container.container_entries
      |> Enum.filter(fn entry ->
        entry.entry_type == :parameter_ref and entry.parameter != nil
      end)
      |> Enum.sort_by(& &1.bit_offset)
      |> Enum.map(fn entry ->
        param = entry.parameter
        data_type = param.data_type
        encoding = data_type && data_type.encoding

        %{
          name: param.name,
          bit_offset: entry.bit_offset || 0,
          bit_size: encoding && encoding.size_in_bits,
          data_type: get_base_type_atom(data_type),
          endianness: get_endianness(encoding, container),
          description: param.description || param.short_description,
          # Build conversion info from calibrator if present
          conversion: build_conversion_from_calibrator(data_type)
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

    # Build O(1) lookup map for ConversionStage
    items_by_name = Map.new(items, fn item -> {to_string(item.name), item} end)

    # Build packet definition map
    %{
      id: container.id,
      mission_id: container.mission_id,
      definition_set_id: definition_set_id,
      # target_id is set at runtime by the interface
      target_id: nil,
      name: container.name,
      type_byte: container.packet_type,
      apid: container.apid,
      description: container.description || container.short_description,
      items: items,
      items_by_name: items_by_name,
      field_specs: field_specs
    }
  end

  # Get the base type as an atom for binary extraction
  # Maps MDB base types to BinaryExtractor types (:uint, :int, :float, :string, :block)
  defp get_base_type_atom(nil), do: :uint

  defp get_base_type_atom(%{base_type: nil, encoding: encoding}),
    do: encoding_to_extractor_type(encoding)

  @base_type_map %{
    float: :float,
    string: :string,
    binary: :block,
    boolean: :uint,
    enumerated: :uint,
    aggregate: :block,
    array: :block,
    absolute_time: :uint,
    relative_time: :uint
  }

  defp get_base_type_atom(%{base_type: :integer, encoding: encoding}) do
    if encoding && encoding.signed, do: :int, else: :uint
  end

  defp get_base_type_atom(%{base_type: base_type}) do
    Map.get(@base_type_map, base_type, :uint)
  end

  defp encoding_to_extractor_type(nil), do: :uint
  defp encoding_to_extractor_type(%{encoding_type: :integer, signed: true}), do: :int
  defp encoding_to_extractor_type(%{encoding_type: :integer}), do: :uint
  defp encoding_to_extractor_type(%{encoding_type: :float}), do: :float
  defp encoding_to_extractor_type(%{encoding_type: :string}), do: :string
  defp encoding_to_extractor_type(%{encoding_type: :binary}), do: :block
  defp encoding_to_extractor_type(%{encoding_type: :boolean}), do: :uint
  defp encoding_to_extractor_type(_), do: :uint

  # Get endianness from encoding or container default
  defp get_endianness(nil, container), do: normalize_endianness(container.byte_order)

  defp get_endianness(%{byte_order: nil}, container),
    do: normalize_endianness(container.byte_order)

  defp get_endianness(%{byte_order: byte_order}, _container), do: normalize_endianness(byte_order)

  # Build conversion structure from MDB calibrator (Algorithm)
  # Returns nil if no calibration is needed, otherwise returns the Algorithm struct
  # for apply_db_conversion to handle directly
  defp build_conversion_from_calibrator(nil), do: nil
  defp build_conversion_from_calibrator(%{default_calibrator: nil}), do: nil

  defp build_conversion_from_calibrator(%{default_calibrator: calibrator}) do
    # Return the Algorithm struct directly - apply_db_conversion knows how to handle it
    calibrator
  end
end
