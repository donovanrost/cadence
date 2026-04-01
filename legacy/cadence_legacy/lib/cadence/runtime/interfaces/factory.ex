defmodule Cadence.Runtime.Interfaces.Factory do
  @moduledoc """
  Factory for building transport child specifications based on connection type.

  Maps transport interfaces to the appropriate transport implementation:
  - `:tcp_client` → `TcpClientInterface`
  - `:tcp_server` → `TcpServerInterface`
  - `:udp_client` → `UdpClientInterface` (TODO)
  - `:udp_server` → `UdpServerInterface` (TODO)
  - `:serial` → `SerialInterface` (TODO)

  ## Data Plane Architecture

  This factory accepts transport interfaces loaded once at supervisor startup.
  No database calls happen during runtime.

  ## Example

      transport = %Interface{
        id: "abc-123",
        mission_id: "mission-1",
        connection_type: :tcp_client,
        host: "192.168.1.100",
        port: 8080,
        target_ids: ["target-1"]
      }

      child_spec = Factory.child_spec_for(transport)
      # Returns a child_spec for the transport GenServer
  """

  alias Cadence.Transports.Interface

  alias Cadence.Runtime.Interfaces.{TcpClientInterface, TcpServerInterface}

  @doc """
  Builds a child specification for the given transport interface.

  Returns a child_spec suitable for starting under a DynamicSupervisor.
  Raises if the connection_type is not implemented yet.
  """
  def child_spec_for(%Interface{} = transport) do
    module = module_for_connection_type(transport.type, transport.endpoint)
    {module, transport}
  end

  @doc """
  Returns the GenServer module for a given transport type and endpoint.
  Raises `RuntimeError` if the connection type is not yet implemented.
  """
  def module_for_connection_type(type, endpoint) do
    case normalize_connection_type(type, endpoint) do
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
  def connection_type_implemented?(type, endpoint) do
    case normalize_connection_type(type, endpoint) do
      :tcp_client -> true
      :tcp_server -> true
      _ -> false
    end
  end

  ## Private Functions

  defp normalize_connection_type(type, endpoint) when is_binary(type) or is_atom(type) do
    normalized = normalize_type_atom(type)
    mode = endpoint_mode(endpoint)

    case normalized do
      :tcp -> tcp_connection_type(mode)
      :udp -> udp_connection_type(mode)
      other -> other
    end
  end

  defp normalize_type_atom(type) when is_atom(type), do: type

  defp normalize_type_atom(type) when is_binary(type) do
    String.to_existing_atom(type)
  rescue
    ArgumentError -> type
  end

  defp tcp_connection_type("server"), do: :tcp_server
  defp tcp_connection_type(_), do: :tcp_client

  defp udp_connection_type("server"), do: :udp_server
  defp udp_connection_type(_), do: :udp_client

  defp endpoint_mode(endpoint) when is_map(endpoint) do
    Map.get(endpoint, :mode) || Map.get(endpoint, "mode")
  end

  defp endpoint_mode(_), do: nil

  defp raise_not_implemented(connection_type, module_name) do
    raise RuntimeError, """
    Interface type '#{connection_type}' is not yet implemented.

    To implement this interface type:
    1. Create lib/cadence/interfaces/#{String.downcase(module_name)}.ex
    2. Implement the GenServer behaviour similar to TcpClientInterface
    3. Update Factory.module_for_connection_type/2 to return #{module_name}
    4. Update Factory.connection_type_implemented?/2 to return true

    Currently only 'tcp_client' and 'tcp_server' are supported.
    """
  end
end
