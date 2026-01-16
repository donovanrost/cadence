defmodule Cadence.Interfaces.InterfaceSchema do
  @moduledoc """
  Interface schema representing a connection to a target or data source.

  Interfaces handle the physical/network connection. Following the OpenC3 COSMOS
  architecture, each interface:
  - Belongs to exactly one mission
  - Has a connection type (tcp_client, tcp_server, udp, serial, etc.)
  - Manages its own connection state
  - Can handle bidirectional communication (read/write)

  ## Examples

      # TCP client interface (connection only)
      %InterfaceSchema{
        name: "SPACECRAFT_TLM",
        connection_type: "tcp_client",
        host: "192.168.1.100",
        port: 8080,
        auto_reconnect: true
      }

      # UDP server interface for commanding
      %InterfaceSchema{
        name: "GROUND_CMD",
        connection_type: "udp_server",
        bind_port: 9000,
        auto_reconnect: false
      }
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          mission_id: Ecto.UUID.t(),
          name: String.t(),
          connection_type: String.t(),
          host: String.t() | nil,
          port: integer() | nil,
          bind_address: String.t() | nil,
          bind_port: integer() | nil,
          status: String.t(),
          config: map(),
          metadata: map(),
          auto_reconnect: boolean(),
          reconnect_delay_ms: integer(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "interfaces" do
    field :name, :string
    field :connection_type, :string

    # Connection parameters
    field :host, :string
    field :port, :integer
    field :bind_address, :string
    field :bind_port, :integer

    # Connection state
    field :status, :string, default: "disconnected"

    # Additional configuration
    field :config, :map, default: %{}
    field :metadata, :map, default: %{}

    # Auto-reconnect settings
    field :auto_reconnect, :boolean, default: true
    field :reconnect_delay_ms, :integer, default: 5000

    # Associations
    belongs_to :mission, Cadence.Missions.Mission
    has_many :vcids, Cadence.Interfaces.InterfaceVcid, foreign_key: :interface_id

    timestamps(type: :utc_datetime)
  end

  @connection_types [
    "tcp_client",
    "tcp_server",
    "udp_client",
    "udp_server",
    "serial"
  ]

  @status_values [
    "disconnected",
    "connecting",
    "connected",
    "error"
  ]

  @doc """
  Changeset for creating a new interface.
  """
  def changeset(interface, attrs) do
    interface
    |> cast(attrs, [
      :mission_id,
      :name,
      :connection_type,
      :host,
      :port,
      :bind_address,
      :bind_port,
      :status,
      :config,
      :metadata,
      :auto_reconnect,
      :reconnect_delay_ms
    ])
    |> validate_required([:mission_id, :name, :connection_type])
    |> validate_inclusion(:connection_type, @connection_types)
    |> validate_inclusion(:status, @status_values)
    |> validate_connection_params()
    |> foreign_key_constraint(:mission_id)
    |> unique_constraint([:mission_id, :name])
  end

  @doc """
  Changeset for updating interface configuration.
  """
  def update_changeset(interface, attrs) do
    interface
    |> cast(attrs, [
      :name,
      :host,
      :port,
      :bind_address,
      :bind_port,
      :config,
      :metadata,
      :auto_reconnect,
      :reconnect_delay_ms
    ])
    |> validate_required([:name])
    |> validate_connection_params()
  end

  @doc """
  Changeset for updating interface status.
  """
  def status_changeset(interface, attrs) do
    interface
    |> cast(attrs, [:status, :metadata])
    |> validate_required([:status])
    |> validate_inclusion(:status, @status_values)
  end

  # Validate connection-specific parameters
  defp validate_connection_params(changeset) do
    connection_type = get_field(changeset, :connection_type)

    case connection_type do
      type when type in ["tcp_client", "udp_client"] ->
        changeset
        |> validate_required([:host, :port])
        |> validate_number(:port, greater_than: 0, less_than: 65_536)

      type when type in ["tcp_server", "udp_server"] ->
        changeset
        |> validate_required([:bind_port])
        |> validate_number(:bind_port, greater_than: 0, less_than: 65_536)

      "serial" ->
        changeset
        |> validate_required([:host])

      # host is the device path for serial
      _ ->
        changeset
    end
  end

  @doc """
  Updates interface to connected status.
  """
  def mark_connected(interface) do
    status_changeset(interface, %{
      status: "connected",
      metadata: Map.put(interface.metadata || %{}, "last_connected_at", DateTime.utc_now())
    })
  end

  @doc """
  Updates interface to disconnected status.
  """
  def mark_disconnected(interface, reason \\ nil) do
    metadata =
      (interface.metadata || %{})
      |> Map.put("last_disconnected_at", DateTime.utc_now())

    metadata =
      if reason do
        Map.put(metadata, "last_disconnect_reason", reason)
      else
        metadata
      end

    status_changeset(interface, %{
      status: "disconnected",
      metadata: metadata
    })
  end

  @doc """
  Updates interface to error status.
  """
  def mark_error(interface, error) do
    status_changeset(interface, %{
      status: "error",
      metadata:
        Map.merge(interface.metadata || %{}, %{
          "last_error" => error,
          "last_error_at" => DateTime.utc_now()
        })
    })
  end
end
