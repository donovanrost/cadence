defmodule Cadence.Runtime.Interfaces.Factory do
  @moduledoc """
  Factory for building interface child specifications based on connection type.

  Maps Interface domain entities to the appropriate transport implementation:
  - `:tcp_client` → `TcpClientInterface`
  - `:tcp_server` → `TcpServerInterface`
  - `:udp_client` → `UdpClientInterface` (TODO)
  - `:udp_server` → `UdpServerInterface` (TODO)
  - `:serial` → `SerialInterface` (TODO)

  ## Data Plane Architecture

  This factory accepts domain entities (not Ecto schemas) to support the
  Data Plane / Control Plane separation. Interface entities are loaded once
  at supervisor startup and injected into GenServers - no database calls
  happen during runtime.

  ## Example

      interface = %Interface{
        id: "abc-123",
        mission_id: "mission-1",
        connection_type: :tcp_client,
        host: "192.168.1.100",
        port: 8080,
        target_ids: ["target-1"]
      }

      child_spec = Factory.child_spec_for(interface)
      # Returns a child_spec for a per-interface supervisor
  """

  alias Cadence.Domain.Interfaces.Entities.Interface

  alias Cadence.Runtime.Interfaces.{
    PerInterfaceSupervisor,
    TcpClientInterface,
    TcpServerInterface
  }

  @doc """
  Builds a child specification for the given interface domain entity.

  The interface entity should be fully loaded with target_ids.
  No database queries are made - all data comes from the entity.

  Returns a child_spec suitable for starting under a DynamicSupervisor.
  Raises if the connection_type is not implemented yet.
  """
  def child_spec_for(%Interface{} = interface) do
    _ = module_for_connection_type(interface.connection_type)
    {PerInterfaceSupervisor, interface}
  end

  @doc """
  Returns the GenServer module for a given connection type.

  Accepts both atom and string connection types for backwards compatibility.
  Raises `RuntimeError` if the connection type is not yet implemented.
  """
  def module_for_connection_type(connection_type) do
    case normalize_connection_type(connection_type) do
      :tcp_client ->
        TcpClientInterface

      :tcp_server ->
        TcpServerInterface

      :udp_client ->
        raise_not_implemented("udp_client", "UdpClientInterface")

      :udp_server ->
        raise_not_implemented("udp_server", "UdpServerInterface")

      :serial ->
        raise_not_implemented("serial", "SerialInterface")

      other ->
        raise ArgumentError, "Unknown connection_type: #{inspect(other)}"
    end
  end

  @doc """
  Checks if a connection type is currently implemented.
  """
  def connection_type_implemented?(connection_type) do
    case normalize_connection_type(connection_type) do
      :tcp_client -> true
      :tcp_server -> true
      _ -> false
    end
  end

  ## Private Functions

  defp normalize_connection_type(type) when is_atom(type), do: type

  defp normalize_connection_type(type) when is_binary(type) do
    String.to_existing_atom(type)
  rescue
    ArgumentError -> type
  end

  defp raise_not_implemented(connection_type, module_name) do
    raise RuntimeError, """
    Interface type '#{connection_type}' is not yet implemented.

    To implement this interface type:
    1. Create lib/cadence/interfaces/#{String.downcase(module_name)}.ex
    2. Implement the GenServer behaviour similar to TcpClientInterface
    3. Update Factory.module_for_connection_type/1 to return #{module_name}
    4. Update Factory.connection_type_implemented?/1 to return true

    Currently only 'tcp_client' and 'tcp_server' are supported.
    """
  end
end
