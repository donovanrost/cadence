defmodule Cadence.Runtime.Interfaces.TcpServerInterface do
  @moduledoc """
  TCP Server interface for receiving telemetry from multiple spacecraft or simulators.

  This GenServer listens on a configured port and accepts multiple simultaneous
  TCP client connections. Downlink processing is delegated to the DownlinkPipeline.
  Uplink encoding is delegated to the UplinkPipeline.

  ## Data Plane Architecture

  This GenServer receives a domain entity at startup - no database calls are made
  during runtime. Configuration changes are handled via PubSub events.

  ## Features

  - Accepts multiple concurrent client connections
  - Automatic client disconnect handling
  - Statistics tracking per client and overall
  - Integration with Phoenix.PubSub telemetry pipeline

  ## Configuration (via Interface Entity)

  - `bind_port` - Port to listen on (required)
  - `bind_address` - Address to bind to (default: "0.0.0.0")
  - `config.max_clients` - Maximum concurrent clients (default: 100)
  - `config.client_timeout` - Client idle timeout in ms (default: 300000)

  ## Downlink Pipeline Architecture

  Downlink processing is handled outside this GenServer to keep transport
  concerns separate from packet framing and decoding.
  """

  use GenServer
  require Logger

  alias Cadence.CCSDS.SDLP.TM.FrameCodec, as: TMFrameCodec
  alias Cadence.CCSDS.TC.TransferFrame
  alias Cadence.Domain.Interfaces.Entities.Interface
  alias Cadence.Interfaces.Events.InterfaceConnectionEvent
  alias Cadence.Runtime.Interfaces.SDLPConfig
  alias Cadence.Runtime.Telemetry.DownlinkPipeline
  alias Cadence.Time, as: CadenceTime
  alias Cadence.Time.Timer, as: TimeTimer

  @registry Cadence.MissionRegistry

  defmodule State do
    @moduledoc false
    defstruct [
      :interface,
      :target_ids,
      :listen_socket,
      :bind_address,
      :bind_port,
      :max_clients,
      :client_timeout,
      :routing_mode,
      :routing_static,
      :sdlp_config,
      clients: %{},
      listening: false,
      total_clients_connected: 0,
      bytes_received: 0,
      bytes_sent: 0,
      packets_received: 0
    ]
  end

  defmodule ClientState do
    @moduledoc false
    defstruct [
      :socket,
      :remote_address,
      :remote_port,
      :connected_at,
      :client_id,
      :scid,
      :vcid,
      :frame_buffer,
      :route_source,
      bytes_received: 0,
      bytes_sent: 0,
      packets_received: 0
    ]
  end

  ## Client API

  @doc """
  Starts the TCP server interface with the given Interface entity.

  The entity contains all configuration - no database lookups are performed.
  """
  def start_link(%Interface{} = interface) do
    name = {:via, Registry, {@registry, {:interface, interface.mission_id, interface.id}}}
    GenServer.start_link(__MODULE__, interface, name: name)
  end

  @doc """
  Gets server statistics including client information.
  """
  def stats(pid) do
    GenServer.call(pid, :get_stats)
  end

  @doc """
  Lists all connected clients with their information.
  """
  def list_clients(pid) do
    GenServer.call(pid, :list_clients)
  end

  @doc """
  Sends data to all connected clients.
  """
  def broadcast(pid, data) do
    GenServer.call(pid, {:send_data, data, :all})
  end

  @doc """
  Sends data to a specific client by socket.
  """
  def send_to_client(pid, client_socket, data) do
    GenServer.call(pid, {:send_data, data, {:client, client_socket}})
  end

  ## Server Callbacks

  @impl true
  def init(%Interface{} = interface) do
    config = interface_config(interface)
    target_ids = target_ids_for_interface(interface)
    bind_address = bind_address_for_interface(interface)
    max_clients = config_value(config, "max_clients", :max_clients, 100)
    client_timeout = config_value(config, "client_timeout", :client_timeout, 300_000)

    Logger.info("""
    Starting TCP Server Interface #{interface.name}:
      mission_id: #{interface.mission_id}
      interface_id: #{interface.id}
      bind_address: #{bind_address}
      bind_port: #{interface.bind_port}
      target_ids: #{inspect(target_ids)}
    """)

    state = %State{
      interface: interface,
      target_ids: target_ids,
      bind_address: bind_address,
      bind_port: interface.bind_port,
      max_clients: max_clients,
      client_timeout: client_timeout,
      routing_mode: parse_routing_mode(config),
      routing_static: parse_routing_static(config),
      sdlp_config: SDLPConfig.fetch(interface),
      clients: %{}
    }

    # Start listening asynchronously
    send(self(), :listen)

    {:ok, state}
  end

  @impl true
  def handle_info(:listen, state) do
    ip_tuple = parse_bind_address(state.bind_address)

    listen_opts = [
      :binary,
      active: false,
      reuseaddr: true,
      packet: :raw,
      ip: ip_tuple
    ]

    case :gen_tcp.listen(state.bind_port, listen_opts) do
      {:ok, listen_socket} ->
        Logger.info("TCP server listening on #{state.bind_address}:#{state.bind_port}")
        send(self(), :accept)
        {:noreply, %{state | listen_socket: listen_socket, listening: true}}

      {:error, reason} ->
        Logger.error("Failed to listen on port #{state.bind_port}: #{inspect(reason)}")
        {:stop, {:listen_error, reason}, state}
    end
  end

  @impl true
  def handle_info(:accept, %State{listen_socket: listen_socket} = state) do
    case :gen_tcp.accept(listen_socket, 100) do
      {:ok, client_socket} ->
        handle_client_accept(client_socket, state)

      {:error, :timeout} ->
        send(self(), :accept)
        {:noreply, state}

      {:error, reason} ->
        Logger.error("Accept error: #{inspect(reason)}")
        TimeTimer.send_after(self(), :accept, 1000)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:tcp, client_socket, data}, state) do
    case Map.get(state.clients, client_socket) do
      nil ->
        Logger.warning("Received data from unknown client socket")
        {:noreply, state}

      client_state ->
        handle_client_data(client_socket, data, client_state, state)
    end
  end

  @impl true
  def handle_info({:tcp_closed, client_socket}, state) do
    case Map.get(state.clients, client_socket) do
      nil ->
        {:noreply, state}

      client_state ->
        Logger.info(
          "Client #{client_state.remote_address}:#{client_state.remote_port} disconnected"
        )

        handle_client_disconnect(client_socket, state)
    end
  end

  @impl true
  def handle_info({:tcp_error, client_socket, reason}, state) do
    Logger.error("TCP error on client socket: #{inspect(reason)}")
    handle_client_disconnect(client_socket, state)
  end

  @impl true
  def handle_cast({:downlink_packets, connection_id, count}, state) do
    case Map.get(state.clients, connection_id) do
      nil ->
        {:noreply, state}

      client_state ->
        updated_client_state = %{
          client_state
          | packets_received: client_state.packets_received + count
        }

        new_clients = Map.put(state.clients, connection_id, updated_client_state)

        {:noreply,
         %{
           state
           | clients: new_clients,
             packets_received: state.packets_received + count
         }}
    end
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      mission_id: state.interface.mission_id,
      interface_id: state.interface.id,
      listening: state.listening,
      bind_port: state.bind_port,
      connected_clients: map_size(state.clients),
      total_clients_connected: state.total_clients_connected,
      bytes_received: state.bytes_received,
      bytes_sent: state.bytes_sent,
      packets_received: state.packets_received,
      routing_mode: state.routing_mode
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call(:list_clients, _from, state) do
    clients =
      Enum.map(state.clients, fn {_socket, client_state} ->
        %{
          remote_address: client_state.remote_address,
          remote_port: client_state.remote_port,
          connected_at: client_state.connected_at,
          client_id: client_state.client_id,
          scid: client_state.scid,
          vcid: client_state.vcid,
          route_source: client_state.route_source,
          bytes_received: client_state.bytes_received,
          bytes_sent: client_state.bytes_sent,
          packets_received: client_state.packets_received
        }
      end)

    {:reply, clients, state}
  end

  # Command dispatch from TargetDispatcher.
  #
  # By default this broadcasts to all clients. If `config.routing` is set to
  # `scid_vcid`, uplink frames are decoded and routed to the matching client.
  #
  # TODO: When command packets include routing hints, prefer APID-based routing.
  @impl true
  def handle_call({:send_data, data}, _from, state) do
    {reply, next_state} = dispatch_uplink(state, data)
    {:reply, reply, next_state}
  end

  @impl true
  def handle_call({:send_data, data, :all}, _from, state) do
    results =
      Enum.map(state.clients, fn {socket, _client_state} ->
        :gen_tcp.send(socket, data)
      end)

    successful = Enum.count(results, fn result -> result == :ok end)
    {:reply, {:ok, successful}, state}
  end

  @impl true
  def handle_call({:send_data, data, {:client, socket}}, _from, state) do
    case Map.get(state.clients, socket) do
      nil ->
        {:reply, {:error, :client_not_found}, state}

      _client_state ->
        result = :gen_tcp.send(socket, data)
        {:reply, result, state}
    end
  end

  def handle_call(:connected?, _from, state) do
    {:reply, map_size(state.clients) > 0, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Close all client sockets
    Enum.each(state.clients, fn {socket, _client_state} ->
      :gen_tcp.close(socket)
    end)

    # Close listen socket
    if state.listen_socket, do: :gen_tcp.close(state.listen_socket)

    :ok
  end

  ## Private Functions

  defp handle_client_accept(client_socket, state) do
    {:ok, {address, port}} = :inet.peername(client_socket)
    address_str = :inet.ntoa(address) |> to_string()

    Logger.info("New client connected from #{address_str}:#{port}")

    if map_size(state.clients) >= state.max_clients do
      reject_client(client_socket, state)
    else
      accept_client(client_socket, address_str, port, state)
    end
  end

  defp reject_client(client_socket, state) do
    Logger.warning("Max clients (#{state.max_clients}) reached, rejecting connection")
    :gen_tcp.close(client_socket)
    send(self(), :accept)
    {:noreply, state}
  end

  defp accept_client(client_socket, address_str, port, state) do
    client_id = state.total_clients_connected + 1

    client_state = %ClientState{
      socket: client_socket,
      remote_address: address_str,
      remote_port: port,
      connected_at: CadenceTime.now(),
      client_id: client_id,
      frame_buffer: <<>>
    }

    :inet.setopts(client_socket, active: true)

    client_state = apply_static_route(client_state, state.routing_static)

    new_clients = Map.put(state.clients, client_socket, client_state)
    send(self(), :accept)

    new_state = %{
      state
      | clients: new_clients,
        total_clients_connected: state.total_clients_connected + 1
    }

    DownlinkPipeline.reset_connection(
      state.interface.mission_id,
      state.interface.id,
      client_socket
    )

    # Logger.debug(
    #   "Accepted client #{address_str}:#{port}, total=#{map_size(new_clients)} (interface #{state.interface.id})",
    #   mission_id: state.interface.mission_id
    # )

    maybe_broadcast_connect(state, new_state, client_state)
    {:noreply, new_state}
  end

  defp maybe_broadcast_connect(state, new_state, client_state) do
    if map_size(state.clients) == 0 do
      broadcast_connection_event(new_state, :disconnected, :connected, client_state)
    end
  end

  defp handle_client_data(client_socket, data, client_state, state) do
    updated_client_state = %{
      client_state
      | bytes_received: client_state.bytes_received + byte_size(data)
    }

    updated_client_state = maybe_update_route(updated_client_state, data, state)

    Logger.debug(
      "TCP #{state.interface.id} received #{byte_size(data)} bytes from #{client_state.remote_address}:#{client_state.remote_port}",
      mission_id: state.interface.mission_id
    )

    DownlinkPipeline.ingest(
      state.interface.mission_id,
      state.interface.id,
      client_socket,
      data,
      downlink_metadata(state, updated_client_state)
    )

    new_clients = Map.put(state.clients, client_socket, updated_client_state)

    {:noreply,
     %{
       state
       | clients: new_clients,
         bytes_received: state.bytes_received + byte_size(data)
     }}
  end

  defp warn_if_broadcasting(count) when count > 1 do
    Logger.warning("Broadcasting command to #{count} clients - routing mode is broadcast")
  end

  defp warn_if_broadcasting(_count), do: :ok

  defp dispatch_uplink(state, data) do
    case map_size(state.clients) do
      0 ->
        {{:error, :no_clients_connected}, state}

      count ->
        dispatch_uplink_with_clients(state, data, count)
    end
  end

  defp dispatch_uplink_with_clients(state, data, count) do
    case route_uplink(state, data) do
      {:client, socket} ->
        send_to_client_socket(socket, data, state)

      :broadcast ->
        warn_if_broadcasting(count)

        {successful, failed} = send_to_all_clients(state.clients, data)
        updated = update_bytes_sent(state, data, successful)
        reply_for_broadcast(successful, failed, updated, state)

      {:error, reason} ->
        {{:error, :routing_failed, reason}, state}
    end
  end

  defp send_to_client_socket(socket, data, state) do
    case :gen_tcp.send(socket, data) do
      :ok -> {:ok, update_bytes_sent(state, data, 1)}
      {:error, reason} -> {{:error, :send_failed, reason}, state}
    end
  end

  defp route_uplink(%{routing_mode: :broadcast}, _data), do: :broadcast

  defp route_uplink(%{routing_mode: :scid_vcid} = state, data) do
    with {:ok, {scid, vcid}} <- extract_uplink_route(state, data),
         {:ok, socket} <- lookup_client_socket(state.clients, scid, vcid) do
      {:client, socket}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp route_uplink(_state, _data), do: :broadcast

  defp extract_uplink_route(%{sdlp_config: {:ok, %{opts: opts}}}, data) do
    profile = opts[:uplink_profile] || opts[:profile]
    frame_size = opts[:uplink_frame_size] || opts[:frame_size]

    cond do
      is_nil(frame_size) ->
        {:error, :missing_frame_size}

      profile == :tm ->
        decode_tm_route(data, frame_size)

      profile == :tc ->
        decode_tc_route(data, frame_size)

      true ->
        {:error, :unsupported_profile}
    end
  end

  defp extract_uplink_route(_state, _data), do: {:error, :routing_unavailable}

  defp decode_tm_route(data, frame_size) do
    {:ok, frames, _rest} = TMFrameCodec.decode(data, frame_size: frame_size)

    case frames do
      [frame | _] -> {:ok, {frame.scid, frame.vcid}}
      [] -> {:error, :no_frames}
    end
  end

  defp decode_tc_route(data, frame_size) do
    case TransferFrame.decode(data, frame_size: frame_size) do
      {:ok, [frame | _], _rest} -> {:ok, {frame.scid, frame.vcid}}
      {:ok, [], _rest} -> {:error, :no_frames}
      {:error, reason} -> {:error, reason}
    end
  end

  defp lookup_client_socket(clients, scid, vcid) do
    matches =
      clients
      |> Enum.filter(fn {_socket, client_state} ->
        client_state.scid == scid and client_state.vcid == vcid
      end)

    case matches do
      [{socket, _client}] -> {:ok, socket}
      [] -> {:error, :route_not_found}
      _ -> {:error, :ambiguous_route}
    end
  end

  defp maybe_update_route(%{route_source: :static} = client_state, _data, _state),
    do: client_state

  defp maybe_update_route(client_state, data, %{routing_mode: :scid_vcid} = state) do
    case state.sdlp_config do
      {:ok, %{opts: opts}} ->
        update_route_from_tm(client_state, data, opts)

      _ ->
        client_state
    end
  end

  defp maybe_update_route(client_state, _data, _state), do: client_state

  defp update_route_from_tm(client_state, data, opts) do
    frame_size = opts[:frame_size]
    profile = opts[:profile]

    cond do
      profile != :tm ->
        client_state

      not is_integer(frame_size) ->
        client_state

      true ->
        do_update_route_from_tm(client_state, data, frame_size)
    end
  end

  defp do_update_route_from_tm(client_state, data, frame_size) do
    buffer = (client_state.frame_buffer || <<>>) <> data
    {:ok, frames, rest} = TMFrameCodec.decode(buffer, frame_size: frame_size)

    case List.last(frames) do
      nil ->
        %{client_state | frame_buffer: rest}

      frame ->
        %{
          client_state
          | frame_buffer: rest,
            scid: frame.scid,
            vcid: frame.vcid,
            route_source: :learned
        }
    end
  end

  defp send_to_all_clients(clients, data) do
    Enum.reduce(clients, {0, 0}, fn {socket, client_state}, {ok, err} ->
      case :gen_tcp.send(socket, data) do
        :ok ->
          # Logger.debug(
          #   "Sent #{byte_size(data)} bytes to #{client_state.remote_address}:#{client_state.remote_port}"
          # )

          {ok + 1, err}

        {:error, reason} ->
          Logger.warning(
            "Failed to send to #{client_state.remote_address}:#{client_state.remote_port}: #{inspect(reason)}"
          )

          {ok, err + 1}
      end
    end)
  end

  defp update_bytes_sent(state, data, successful) do
    %{state | bytes_sent: state.bytes_sent + byte_size(data) * successful}
  end

  defp reply_for_broadcast(successful, _failed, new_state, _state) when successful > 0 do
    {:ok, new_state}
  end

  defp reply_for_broadcast(_successful, failed, _new_state, state) do
    {{:error, :all_sends_failed, failed}, state}
  end

  defp handle_client_disconnect(client_socket, state) do
    client_state = Map.get(state.clients, client_socket)
    :gen_tcp.close(client_socket)
    new_clients = Map.delete(state.clients, client_socket)
    new_state = %{state | clients: new_clients}

    DownlinkPipeline.drop_connection(
      state.interface.mission_id,
      state.interface.id,
      client_socket
    )

    # Broadcast disconnection event when last client disconnects
    if map_size(new_clients) == 0 and map_size(state.clients) > 0 do
      broadcast_connection_event(new_state, :connected, :disconnected, client_state)
    end

    {:noreply, new_state}
  end

  defp broadcast_connection_event(state, previous_state, new_state, client_state) do
    client_info =
      if client_state do
        %{
          "remote_address" => client_state.remote_address,
          "remote_port" => client_state.remote_port
        }
      end

    event =
      InterfaceConnectionEvent.new(%{
        mission_id: state.interface.mission_id,
        interface_id: state.interface.id,
        interface_name: state.interface.name,
        previous_state: previous_state,
        new_state: new_state,
        client_count: map_size(state.clients),
        client_info: client_info
      })

    Logger.info("Interface connection event: #{InterfaceConnectionEvent.describe(event)}")
    InterfaceConnectionEvent.broadcast(event)
  end

  defp interface_config(%Interface{config: config}) when is_map(config), do: config
  defp interface_config(_), do: %{}

  defp target_ids_for_interface(%Interface{target_ids: target_ids})
       when is_list(target_ids) and target_ids != [],
       do: target_ids

  defp target_ids_for_interface(_), do: ["unknown"]

  defp bind_address_for_interface(%Interface{bind_address: address})
       when is_binary(address) and address != "",
       do: address

  defp bind_address_for_interface(_), do: "0.0.0.0"

  defp config_value(config, string_key, atom_key, default) when is_map(config) do
    Map.get(config, string_key) || Map.get(config, atom_key) || default
  end

  defp config_value(_config, _string_key, _atom_key, default), do: default

  defp parse_bind_address(address) when is_binary(address) do
    case :inet.parse_address(String.to_charlist(address)) do
      {:ok, ip_tuple} -> ip_tuple
      {:error, _} -> {0, 0, 0, 0}
    end
  end

  defp parse_bind_address(address) when is_list(address) do
    case :inet.parse_address(address) do
      {:ok, ip_tuple} -> ip_tuple
      {:error, _} -> {0, 0, 0, 0}
    end
  end

  defp parse_bind_address(_), do: {0, 0, 0, 0}

  defp parse_routing_mode(config) when is_map(config) do
    case Map.get(config, "routing") || Map.get(config, :routing) do
      "scid_vcid" -> :scid_vcid
      :scid_vcid -> :scid_vcid
      "broadcast" -> :broadcast
      :broadcast -> :broadcast
      _ -> :broadcast
    end
  end

  defp parse_routing_static(config) when is_map(config) do
    routes = Map.get(config, "routing_static") || Map.get(config, :routing_static) || []

    Enum.reduce(List.wrap(routes), [], fn entry, acc ->
      case normalize_route_entry(entry) do
        {:ok, route} -> [route | acc]
        :error -> acc
      end
    end)
    |> Enum.reverse()
  end

  defp parse_routing_static(_), do: []

  defp normalize_route_entry(entry) when is_map(entry) do
    with {:ok, scid} <- fetch_required_integer(entry, ["scid", :scid]),
         {:ok, vcid} <- fetch_required_integer(entry, ["vcid", :vcid]) do
      {:ok,
       %{
         scid: scid,
         vcid: vcid,
         client_id:
           fetch_optional_integer(entry, ["client_id", :client_id, "client_index", :client_index]),
         remote_address:
           fetch_optional_value(entry, [
             "remote_address",
             :remote_address,
             "client_address",
             :client_address
           ]),
         remote_port: fetch_optional_integer(entry, ["remote_port", :remote_port])
       }}
    else
      _ -> :error
    end
  end

  defp normalize_route_entry(_), do: :error

  defp apply_static_route(client_state, []), do: client_state

  defp apply_static_route(client_state, routes) do
    case find_static_route(routes, client_state) do
      nil ->
        client_state

      route ->
        %{
          client_state
          | scid: route.scid,
            vcid: route.vcid,
            route_source: :static
        }
    end
  end

  defp find_static_route(routes, client_state) do
    Enum.find(routes, fn route ->
      matches_client_id?(route, client_state) or matches_remote?(route, client_state)
    end)
  end

  defp matches_client_id?(%{client_id: nil}, _client_state), do: false

  defp matches_client_id?(%{client_id: client_id}, client_state) do
    client_state.client_id == client_id
  end

  defp matches_remote?(%{remote_address: nil}, _client_state), do: false

  defp matches_remote?(route, client_state) do
    same_address = client_state.remote_address == route.remote_address

    case route.remote_port do
      nil -> same_address
      port -> same_address and client_state.remote_port == port
    end
  end

  defp parse_integer(nil), do: nil
  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_integer(_), do: nil

  defp fetch_optional_value(entry, keys) do
    Enum.find_value(keys, fn key -> Map.get(entry, key) end)
  end

  defp fetch_optional_integer(entry, keys) do
    entry
    |> fetch_optional_value(keys)
    |> parse_integer()
  end

  defp fetch_required_integer(entry, keys) do
    case fetch_optional_integer(entry, keys) do
      nil -> :error
      value -> {:ok, value}
    end
  end

  defp downlink_metadata(state, client_state) do
    %{
      mission_id: state.interface.mission_id,
      stored: false,
      target_id: List.first(state.target_ids) || "unknown",
      received_at: CadenceTime.now(),
      interface_id: state.interface.id,
      client_address: client_state.remote_address,
      client_port: client_state.remote_port
    }
  end
end
