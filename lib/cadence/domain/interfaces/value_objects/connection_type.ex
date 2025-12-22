defmodule Cadence.Domain.Interfaces.ValueObjects.ConnectionType do
  @moduledoc """
  Value object representing interface connection types.

  ## Connection Types

  - `:tcp_client` - Connects to a remote TCP server
  - `:tcp_server` - Listens for incoming TCP connections
  - `:udp_client` - Sends UDP datagrams to a remote endpoint
  - `:udp_server` - Receives UDP datagrams on a local port
  - `:serial` - Serial port connection (RS-232, RS-485, etc.)

  ## Connection Requirements

  Different connection types require different configuration:

  - **Client types** (`tcp_client`, `udp_client`): require `host` and `port`
  - **Server types** (`tcp_server`, `udp_server`): require `bind_port`
  - **Serial**: requires device path in `host` field
  """

  @type t :: :tcp_client | :tcp_server | :udp_client | :udp_server | :serial

  @values [:tcp_client, :tcp_server, :udp_client, :udp_server, :serial]

  @client_types [:tcp_client, :udp_client]
  @server_types [:tcp_server, :udp_server]
  @implemented_types [:tcp_client, :tcp_server]

  @doc """
  Returns all valid connection type values.
  """
  @spec values() :: [t()]
  def values, do: @values

  @doc """
  Returns true if the given value is a valid connection type.
  """
  @spec valid?(term()) :: boolean()
  def valid?(value) when value in @values, do: true
  def valid?(_), do: false

  @doc """
  Validates a connection type value.
  """
  @spec validate(term()) :: :ok | {:error, :invalid_connection_type}
  def validate(value) when value in @values, do: :ok
  def validate(_), do: {:error, :invalid_connection_type}

  @doc """
  Parses a string or atom into a connection type.

  Returns `{:ok, type}` or `{:error, :invalid_connection_type}`.
  """
  @spec parse(String.t() | atom()) :: {:ok, t()} | {:error, :invalid_connection_type}
  def parse(value) when is_atom(value) and value in @values, do: {:ok, value}

  def parse(value) when is_binary(value) do
    case String.downcase(value) do
      "tcp_client" -> {:ok, :tcp_client}
      "tcp_server" -> {:ok, :tcp_server}
      "udp_client" -> {:ok, :udp_client}
      "udp_server" -> {:ok, :udp_server}
      "serial" -> {:ok, :serial}
      _ -> {:error, :invalid_connection_type}
    end
  end

  def parse(_), do: {:error, :invalid_connection_type}

  @doc """
  Returns true if this is a client connection type (initiates connections).
  """
  @spec client?(t()) :: boolean()
  def client?(type) when type in @client_types, do: true
  def client?(_), do: false

  @doc """
  Returns true if this is a server connection type (accepts connections).
  """
  @spec server?(t()) :: boolean()
  def server?(type) when type in @server_types, do: true
  def server?(_), do: false

  @doc """
  Returns true if this is a TCP-based connection type.
  """
  @spec tcp?(t()) :: boolean()
  def tcp?(:tcp_client), do: true
  def tcp?(:tcp_server), do: true
  def tcp?(_), do: false

  @doc """
  Returns true if this is a UDP-based connection type.
  """
  @spec udp?(t()) :: boolean()
  def udp?(:udp_client), do: true
  def udp?(:udp_server), do: true
  def udp?(_), do: false

  @doc """
  Returns true if this connection type is currently implemented.

  Only implemented types can be started as runtime GenServers.
  """
  @spec implemented?(t()) :: boolean()
  def implemented?(type) when type in @implemented_types, do: true
  def implemented?(_), do: false

  @doc """
  Returns the list of implemented connection types.
  """
  @spec implemented_types() :: [t()]
  def implemented_types, do: @implemented_types

  @doc """
  Returns the display name for a connection type.
  """
  @spec display_name(t()) :: String.t()
  def display_name(:tcp_client), do: "TCP Client"
  def display_name(:tcp_server), do: "TCP Server"
  def display_name(:udp_client), do: "UDP Client"
  def display_name(:udp_server), do: "UDP Server"
  def display_name(:serial), do: "Serial"

  @doc """
  Returns the required configuration fields for a connection type.
  """
  @spec required_fields(t()) :: [atom()]
  def required_fields(:tcp_client), do: [:host, :port]
  def required_fields(:tcp_server), do: [:bind_port]
  def required_fields(:udp_client), do: [:host, :port]
  def required_fields(:udp_server), do: [:bind_port]
  def required_fields(:serial), do: [:host]

  @doc """
  Returns an icon name for the connection type (for UI).
  """
  @spec icon(t()) :: String.t()
  def icon(:tcp_client), do: "arrow-right-circle"
  def icon(:tcp_server), do: "server"
  def icon(:udp_client), do: "arrow-right"
  def icon(:udp_server), do: "inbox"
  def icon(:serial), do: "cpu"
end
