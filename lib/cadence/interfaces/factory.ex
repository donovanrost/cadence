defmodule Cadence.Interfaces.Factory do
  @moduledoc """
  Factory for building interface child specifications based on connection type.

  Maps interface database records to the appropriate GenServer implementation:
  - `tcp_client` → `TcpClientInterface`
  - `tcp_server` → `TcpServerInterface`
  - `udp_client` → `UdpClientInterface` (TODO)
  - `udp_server` → `UdpServerInterface` (TODO)
  - `serial` → `SerialInterface` (TODO)

  ## Example

      interface = %Interface{
        id: "abc-123",
        mission_id: "mission-1",
        connection_type: "tcp_client",
        host: "192.168.1.100",
        port: 8080,
        config: %{target_id: "target-1"}
      }

      child_spec = Factory.child_spec_for(interface)
      # Returns a child_spec for TcpClientInterface

  """

  alias Cadence.Interfaces
  alias Cadence.Interfaces.InterfaceSchema
  alias Cadence.Interfaces.TcpClientInterface
  alias Cadence.Interfaces.TcpServerInterface

  @doc """
  Builds a child specification for the given interface.

  Returns a child_spec suitable for starting under a DynamicSupervisor.
  Raises if the connection_type is not implemented yet.
  """
  def child_spec_for(%InterfaceSchema{} = interface) do
    module = module_for_connection_type(interface.connection_type)

    # Build the configuration for the interface GenServer
    # Format: [mission_id: ..., interface_id: ..., config: %{...}]
    opts = [
      mission_id: interface.mission_id,
      interface_id: interface.id,
      name: interface.name,
      config: build_connection_config(interface)
    ]

    # Return child spec tuple
    {module, opts}
  end

  @doc """
  Returns the GenServer module for a given connection type.

  Raises `RuntimeError` if the connection type is not yet implemented.
  """
  def module_for_connection_type(connection_type) do
    case connection_type do
      "tcp_client" ->
        TcpClientInterface

      "tcp_server" ->
        TcpServerInterface

      "udp_client" ->
        raise_not_implemented("udp_client", "UdpClientInterface")

      "udp_server" ->
        raise_not_implemented("udp_server", "UdpServerInterface")

      "serial" ->
        raise_not_implemented("serial", "SerialInterface")

      other ->
        raise ArgumentError, "Unknown connection_type: #{inspect(other)}"
    end
  end

  @doc """
  Checks if a connection type is currently implemented.
  """
  def connection_type_implemented?(connection_type) do
    case connection_type do
      "tcp_client" -> true
      "tcp_server" -> true
      _ -> false
    end
  end

  ## Private Functions

  defp build_connection_config(%InterfaceSchema{connection_type: "tcp_client"} = interface) do
    # Query associated targets from join table
    target_ids = get_targets_for_interface(interface)

    # TCP clients connect to a single target - use first or "unknown"
    target_id = List.first(target_ids) || "unknown"

    # Build config map for TcpClientInterface
    base_config = %{
      interface_id: interface.id,
      target_id: target_id,
      host: interface.host,
      port: interface.port,
      reconnect_interval: interface.reconnect_delay_ms || 5000
    }

    # Merge with additional config from database if present
    case interface.config do
      nil -> base_config
      config when is_map(config) -> Map.merge(base_config, config)
    end
  end

  defp build_connection_config(%InterfaceSchema{connection_type: "tcp_server"} = interface) do
    # Query associated targets from join table
    target_ids = get_targets_for_interface(interface)

    # TCP servers can accept connections from multiple targets
    # If no targets configured, use ["unknown"] as fallback
    target_ids = if Enum.empty?(target_ids), do: ["unknown"], else: target_ids

    base_config = %{
      interface_id: interface.id,
      target_ids: target_ids,
      bind_address: interface.bind_address || "0.0.0.0",
      bind_port: interface.bind_port,
      max_clients:
        get_in(interface.config, ["max_clients"]) || get_in(interface.config, [:max_clients]) ||
          100,
      client_timeout:
        get_in(interface.config, ["client_timeout"]) ||
          get_in(interface.config, [:client_timeout]) || 300_000
    }

    # Merge with additional config from database if present
    case interface.config do
      nil -> base_config
      config when is_map(config) -> Map.merge(base_config, config)
    end
  end

  defp build_connection_config(%InterfaceSchema{connection_type: type})
       when type in ["udp_client", "udp_server"] do
    # TODO: Implement UDP-specific config
    %{}
  end

  defp build_connection_config(%InterfaceSchema{connection_type: "serial"}) do
    # Serial interfaces typically use config JSON for port, baud rate, etc.
    # TODO: Implement serial-specific config parsing
    %{}
  end

  # Query associated targets from target_interfaces join table
  defp get_targets_for_interface(%InterfaceSchema{} = interface) do
    targets = Interfaces.list_targets_for_interface(interface)

    # Return list of target identifiers
    Enum.map(targets, & &1.identifier)
  end

  defp raise_not_implemented(connection_type, module_name) do
    raise RuntimeError, """
    Interface type '#{connection_type}' is not yet implemented.

    To implement this interface type:
    1. Create lib/cadence/interfaces/#{String.downcase(module_name)}.ex
    2. Implement the GenServer behaviour similar to TcpClientInterface
    3. Update Factory.module_for_connection_type/1 to return #{module_name}
    4. Update Factory.connection_type_implemented?/1 to return true

    Currently only 'tcp_client' is supported.
    """
  end
end
