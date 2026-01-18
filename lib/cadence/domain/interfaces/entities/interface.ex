defmodule Cadence.Domain.Interfaces.Entities.Interface do
  @moduledoc """
  Pure domain entity representing a network interface configuration.

  Interfaces handle the physical/network connection to data sources.
  Following the OpenC3 COSMOS architecture, each interface:
  - Belongs to exactly one mission
  - Has a connection type (tcp_client, tcp_server, udp, serial, etc.)
  - Can handle bidirectional communication

  **IMPORTANT**: This entity represents configuration only, NOT runtime state.
  Interface status (connected, disconnected, etc.) is managed by GenServer
  processes and broadcast via PubSub. Status is never persisted to the database
  during normal operation.

  ## Data Plane Compatibility

  This entity is designed to be serializable and ETS-friendly for future
  Data Plane / Control Plane architecture:
  - Simple struct with no Ecto associations
  - target_ids are denormalized (no joins needed at runtime)

  ## Usage

      {:ok, interface} = Interface.new(%{
        mission_id: "mission-123",
        name: "SPACECRAFT_TLM",
        connection_type: :tcp_client,
        host: "192.168.1.100",
        port: 8080
      })
  """

  alias Cadence.Domain.Interfaces.ValueObjects.ConnectionType
  alias Cadence.Time, as: CadenceTime

  @type t :: %__MODULE__{
          id: String.t() | nil,
          mission_id: String.t(),
          name: String.t(),
          connection_type: ConnectionType.t(),
          host: String.t() | nil,
          port: non_neg_integer() | nil,
          bind_address: String.t() | nil,
          bind_port: non_neg_integer() | nil,
          auto_reconnect: boolean(),
          reconnect_delay_ms: non_neg_integer(),
          config: map(),
          metadata: map(),
          target_ids: [String.t()],
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @enforce_keys [:mission_id, :name, :connection_type]
  defstruct [
    :id,
    :mission_id,
    :name,
    :connection_type,
    :host,
    :port,
    :bind_address,
    :bind_port,
    :created_at,
    :updated_at,
    auto_reconnect: true,
    reconnect_delay_ms: 5000,
    config: %{},
    metadata: %{},
    target_ids: []
  ]

  @default_reconnect_delay_ms 5000

  # ===========================================================================
  # Construction
  # ===========================================================================

  @doc """
  Creates a new Interface entity.

  ## Attributes

  Required:
  - `:mission_id` - ID of the parent mission
  - `:name` - Interface display name (unique within mission)
  - `:connection_type` - Type of connection (:tcp_client, :tcp_server, etc.)

  Conditionally Required (based on connection_type):
  - `:host` and `:port` - Required for client types
  - `:bind_port` - Required for server types

  Optional:
  - `:bind_address` - Address to bind for servers (default: "0.0.0.0")
  - `:auto_reconnect` - Whether to auto-reconnect (default: true)
  - `:reconnect_delay_ms` - Delay between reconnect attempts (default: 5000)
  - `:config` - Additional configuration map
  - `:metadata` - Metadata map
  - `:target_ids` - List of target IDs this interface routes to
  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    with :ok <- validate_required(attrs),
         {:ok, connection_type} <- parse_connection_type(attrs[:connection_type]),
         :ok <- validate_connection_params(connection_type, attrs),
         :ok <- validate_name(attrs[:name]) do
      {:ok,
       %__MODULE__{
         id: attrs[:id],
         mission_id: attrs[:mission_id],
         name: attrs[:name],
         connection_type: connection_type,
         host: attrs[:host],
         port: attrs[:port],
         bind_address: attrs[:bind_address],
         bind_port: attrs[:bind_port],
         auto_reconnect: Map.get(attrs, :auto_reconnect, true),
         reconnect_delay_ms: Map.get(attrs, :reconnect_delay_ms, @default_reconnect_delay_ms),
         config: attrs[:config] || %{},
         metadata: attrs[:metadata] || %{},
         target_ids: attrs[:target_ids] || [],
         created_at: attrs[:created_at],
         updated_at: attrs[:updated_at]
       }}
    end
  end

  @doc """
  Updates an interface entity with new attributes.

  Note: connection_type cannot be changed after creation.
  """
  @spec update(t(), map()) :: {:ok, t()} | {:error, term()}
  def update(%__MODULE__{connection_type: conn_type} = interface, attrs) do
    with :ok <- validate_name(attrs[:name] || interface.name),
         :ok <- validate_connection_params(conn_type, Map.merge(to_map(interface), attrs)) do
      {:ok,
       %{
         interface
         | name: attrs[:name] || interface.name,
           host: Map.get(attrs, :host, interface.host),
           port: Map.get(attrs, :port, interface.port),
           bind_address: Map.get(attrs, :bind_address, interface.bind_address),
           bind_port: Map.get(attrs, :bind_port, interface.bind_port),
           auto_reconnect: Map.get(attrs, :auto_reconnect, interface.auto_reconnect),
           reconnect_delay_ms: Map.get(attrs, :reconnect_delay_ms, interface.reconnect_delay_ms),
           config: Map.merge(interface.config, attrs[:config] || %{}),
           metadata: Map.merge(interface.metadata, attrs[:metadata] || %{}),
           target_ids: attrs[:target_ids] || interface.target_ids,
           updated_at: CadenceTime.now()
       }}
    end
  end

  @doc """
  Reconstructs an interface entity from persisted data.

  Unlike `new/1`, this does not run validations as the data
  is assumed to be valid from the database.
  """
  @spec from_persistence(map()) :: t()
  def from_persistence(attrs) do
    %__MODULE__{
      id: attrs[:id],
      mission_id: attrs[:mission_id],
      name: attrs[:name],
      connection_type: parse_connection_type_from_persistence(attrs[:connection_type]),
      host: attrs[:host],
      port: attrs[:port],
      bind_address: attrs[:bind_address],
      bind_port: attrs[:bind_port],
      auto_reconnect: Map.get(attrs, :auto_reconnect, true),
      reconnect_delay_ms: Map.get(attrs, :reconnect_delay_ms, @default_reconnect_delay_ms),
      config: attrs[:config] || %{},
      metadata: attrs[:metadata] || %{},
      target_ids: attrs[:target_ids] || [],
      created_at: attrs[:created_at] || attrs[:inserted_at],
      updated_at: attrs[:updated_at]
    }
  end

  # ===========================================================================
  # Target Management
  # ===========================================================================

  @doc """
  Adds a target ID to the interface's routing.
  """
  @spec add_target(t(), String.t()) :: {:ok, t()}
  def add_target(%__MODULE__{target_ids: ids} = interface, target_id) do
    if target_id in ids do
      {:ok, interface}
    else
      {:ok, %{interface | target_ids: ids ++ [target_id], updated_at: CadenceTime.now()}}
    end
  end

  @doc """
  Removes a target ID from the interface's routing.
  """
  @spec remove_target(t(), String.t()) :: {:ok, t()}
  def remove_target(%__MODULE__{target_ids: ids} = interface, target_id) do
    {:ok, %{interface | target_ids: List.delete(ids, target_id), updated_at: CadenceTime.now()}}
  end

  # ===========================================================================
  # Predicates
  # ===========================================================================

  @doc """
  Returns true if this is a client connection type.
  """
  @spec client?(t()) :: boolean()
  def client?(%__MODULE__{connection_type: type}) do
    ConnectionType.client?(type)
  end

  @doc """
  Returns true if this is a server connection type.
  """
  @spec server?(t()) :: boolean()
  def server?(%__MODULE__{connection_type: type}) do
    ConnectionType.server?(type)
  end

  @doc """
  Returns true if this connection type is implemented.
  """
  @spec implemented?(t()) :: boolean()
  def implemented?(%__MODULE__{connection_type: type}) do
    ConnectionType.implemented?(type)
  end

  @doc """
  Returns the endpoint string for display (e.g., "192.168.1.100:8080").
  """
  @spec endpoint(t()) :: String.t()
  def endpoint(%__MODULE__{connection_type: type} = interface) do
    if ConnectionType.client?(type) do
      "#{interface.host}:#{interface.port}"
    else
      "#{interface.bind_address || "0.0.0.0"}:#{interface.bind_port}"
    end
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp validate_required(attrs) do
    cond do
      is_nil(attrs[:mission_id]) -> {:error, :mission_id_required}
      is_nil(attrs[:name]) -> {:error, :name_required}
      is_nil(attrs[:connection_type]) -> {:error, :connection_type_required}
      true -> :ok
    end
  end

  defp validate_name(name) when is_binary(name) and byte_size(name) > 0, do: :ok
  defp validate_name(_), do: {:error, :invalid_name}

  defp parse_connection_type(type) when is_atom(type) do
    case ConnectionType.validate(type) do
      :ok -> {:ok, type}
      error -> error
    end
  end

  defp parse_connection_type(type) when is_binary(type) do
    ConnectionType.parse(type)
  end

  defp parse_connection_type(_), do: {:error, :invalid_connection_type}

  defp validate_connection_params(type, attrs) do
    required = ConnectionType.required_fields(type)
    missing = Enum.filter(required, &is_nil(attrs[&1]))

    if Enum.empty?(missing) do
      validate_port_ranges(attrs)
    else
      {:error, {:missing_fields, missing}}
    end
  end

  defp validate_port_ranges(attrs) do
    port = attrs[:port]
    bind_port = attrs[:bind_port]

    cond do
      port && (port < 1 || port > 65_535) ->
        {:error, :invalid_port}

      bind_port && (bind_port < 1 || bind_port > 65_535) ->
        {:error, :invalid_bind_port}

      true ->
        :ok
    end
  end

  defp parse_connection_type_from_persistence(type) when is_atom(type), do: type

  defp parse_connection_type_from_persistence(type) when is_binary(type) do
    case ConnectionType.parse(type) do
      {:ok, parsed} -> parsed
      _ -> :tcp_client
    end
  end

  defp parse_connection_type_from_persistence(_), do: :tcp_client

  defp to_map(%__MODULE__{} = interface) do
    %{
      host: interface.host,
      port: interface.port,
      bind_address: interface.bind_address,
      bind_port: interface.bind_port
    }
  end
end
