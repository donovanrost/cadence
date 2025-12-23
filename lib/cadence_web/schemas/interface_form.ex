defmodule CadenceWeb.Schemas.InterfaceForm do
  @moduledoc """
  Embedded schema for interface forms in LiveView.

  This schema provides form validation without database persistence.
  It's used for creating and editing interfaces through the web interface.

  ## Usage

      # In LiveView
      def mount(_params, _session, socket) do
        form = InterfaceForm.changeset() |> to_form()
        {:ok, assign(socket, form: form)}
      end

      def handle_event("validate", %{"interface_form" => params}, socket) do
        form =
          InterfaceForm.changeset(params)
          |> Map.put(:action, :validate)
          |> to_form()

        {:noreply, assign(socket, form: form)}
      end

      def handle_event("save", %{"interface_form" => params}, socket) do
        case InterfaceForm.changeset(params) |> Ecto.Changeset.apply_action(:insert) do
          {:ok, form} ->
            attrs = InterfaceForm.to_domain_attrs(form)
            InterfaceOperations.create(mission_id, attrs)
          {:error, changeset} ->
            {:noreply, assign(socket, form: to_form(changeset))}
        end
      end
  """

  use Ecto.Schema
  import Ecto.Changeset

  @connection_types [:tcp_client, :tcp_server, :udp_client, :udp_server]
  @client_types [:tcp_client, :udp_client]
  @server_types [:tcp_server, :udp_server]

  @primary_key false
  embedded_schema do
    field :name, :string
    field :connection_type, Ecto.Enum, values: @connection_types
    field :host, :string
    field :port, :integer
    field :bind_address, :string
    field :bind_port, :integer
    field :auto_reconnect, :boolean, default: true
    field :reconnect_delay_ms, :integer, default: 5000
    field :config, :map, default: %{}
    field :metadata, :map, default: %{}
    # UI-only fields
    field :direction, Ecto.Enum, values: [:read, :write, :both], default: :read
  end

  @doc """
  Creates a changeset for the interface form.

  ## Examples

      InterfaceForm.changeset(%{name: "SPACECRAFT_TLM", connection_type: :tcp_client, host: "192.168.1.100", port: 8080})
  """
  def changeset(form \\ %__MODULE__{}, attrs \\ %{}) do
    form
    |> cast(attrs, [
      :name,
      :connection_type,
      :host,
      :port,
      :bind_address,
      :bind_port,
      :auto_reconnect,
      :reconnect_delay_ms,
      :config,
      :metadata,
      :direction
    ])
    |> validate_required([:name, :connection_type])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_connection_params()
    |> validate_port_range(:port)
    |> validate_port_range(:bind_port)
    |> validate_number(:reconnect_delay_ms, greater_than: 0, less_than_or_equal_to: 60_000)
  end

  @doc """
  Converts a form struct to domain attributes for creating/updating an interface.
  """
  def to_domain_attrs(%__MODULE__{} = form) do
    %{
      name: form.name,
      connection_type: form.connection_type,
      host: form.host,
      port: form.port,
      bind_address: form.bind_address,
      bind_port: form.bind_port,
      auto_reconnect: form.auto_reconnect,
      reconnect_delay_ms: form.reconnect_delay_ms,
      config: form.config || %{},
      metadata: form.metadata || %{}
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc """
  Creates a form struct from a domain entity for editing.
  """
  def from_entity(%Cadence.Domain.Interfaces.Entities.Interface{} = entity) do
    %__MODULE__{
      name: entity.name,
      connection_type: entity.connection_type,
      host: entity.host,
      port: entity.port,
      bind_address: entity.bind_address,
      bind_port: entity.bind_port,
      auto_reconnect: entity.auto_reconnect,
      reconnect_delay_ms: entity.reconnect_delay_ms,
      config: entity.config || %{},
      metadata: entity.metadata || %{}
    }
  end

  @doc """
  Returns the list of available connection types.
  """
  def connection_types, do: @connection_types

  @doc """
  Returns true if the given connection type is a client type.
  """
  def client_type?(type), do: type in @client_types

  @doc """
  Returns true if the given connection type is a server type.
  """
  def server_type?(type), do: type in @server_types

  # Private helpers

  defp validate_connection_params(changeset) do
    connection_type = get_field(changeset, :connection_type)

    case connection_type do
      type when type in @client_types ->
        changeset
        |> validate_required([:host, :port], message: "is required for client connections")

      type when type in @server_types ->
        changeset
        |> validate_required([:bind_port], message: "is required for server connections")

      _ ->
        changeset
    end
  end

  defp validate_port_range(changeset, field) do
    validate_number(changeset, field,
      greater_than: 0,
      less_than_or_equal_to: 65_535,
      message: "must be between 1 and 65535"
    )
  end
end
