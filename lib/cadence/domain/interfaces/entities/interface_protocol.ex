defmodule Cadence.Domain.Interfaces.Entities.InterfaceProtocol do
  @moduledoc """
  Pure domain entity representing a protocol in an interface's protocol chain.

  Protocols are components that process data as it flows through an interface.
  Following OpenC3 COSMOS architecture:
  - READ protocols execute in order (protocol 0 → 1 → 2 ...)
  - WRITE protocols execute in reverse order (... 2 → 1 → 0)

  ## Usage

      {:ok, protocol} = InterfaceProtocol.new(%{
        interface_id: "interface-123",
        protocol_type: :template,
        protocol_direction: :read,
        order: 0,
        config: %{"sync_pattern_hex" => "1ACFFC1D"}
      })
  """

  alias Cadence.Domain.Interfaces.ValueObjects.DataDirection
  alias Cadence.Domain.Interfaces.ValueObjects.ProtocolType

  @type t :: %__MODULE__{
          id: String.t() | nil,
          interface_id: String.t(),
          protocol_type: ProtocolType.t(),
          protocol_direction: DataDirection.t(),
          config: map(),
          order: non_neg_integer(),
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @enforce_keys [:interface_id, :protocol_type, :order]
  defstruct [
    :id,
    :interface_id,
    :protocol_type,
    :order,
    :created_at,
    :updated_at,
    protocol_direction: :read_write,
    config: %{}
  ]

  @doc """
  Creates a new InterfaceProtocol entity.

  ## Attributes

  Required:
  - `:interface_id` - ID of the parent interface
  - `:protocol_type` - Type of protocol (:ccsds_sdlp, :length, :template, etc.)
  - `:order` - Position in the protocol chain (0-indexed)

  Optional:
  - `:protocol_direction` - Data direction (default: :read_write)
  - `:config` - Protocol-specific configuration map
  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    with :ok <- validate_required(attrs),
         {:ok, protocol_type} <- parse_protocol_type(attrs[:protocol_type]),
         {:ok, direction} <- parse_direction(attrs[:protocol_direction]),
         :ok <- validate_order(attrs[:order]),
         :ok <- validate_config(protocol_type, attrs[:config] || %{}) do
      {:ok,
       %__MODULE__{
         id: attrs[:id],
         interface_id: attrs[:interface_id],
         protocol_type: protocol_type,
         protocol_direction: direction,
         config: attrs[:config] || %{},
         order: attrs[:order],
         created_at: attrs[:created_at],
         updated_at: attrs[:updated_at]
       }}
    end
  end

  @doc """
  Updates a protocol entity with new attributes.
  """
  @spec update(t(), map()) :: {:ok, t()} | {:error, term()}
  def update(%__MODULE__{} = protocol, attrs) do
    with {:ok, direction} <-
           maybe_parse_direction(attrs[:protocol_direction], protocol.protocol_direction),
         {:ok, order} <- maybe_validate_order(attrs[:order], protocol.order),
         config <- Map.merge(protocol.config, attrs[:config] || %{}),
         :ok <- validate_config(protocol.protocol_type, config) do
      {:ok,
       %{
         protocol
         | protocol_direction: direction,
           order: order,
           config: config,
           updated_at: DateTime.utc_now()
       }}
    end
  end

  @doc """
  Reconstructs a protocol entity from persisted data.

  If already an entity struct, returns it as-is (idempotent).
  """
  @spec from_persistence(map() | t()) :: t()
  def from_persistence(%__MODULE__{} = entity), do: entity

  def from_persistence(attrs) when is_map(attrs) do
    %__MODULE__{
      id: attrs[:id],
      interface_id: attrs[:interface_id],
      protocol_type: parse_type_from_persistence(attrs[:protocol_type]),
      protocol_direction: parse_direction_from_persistence(attrs[:protocol_direction]),
      config: attrs[:config] || attrs[:protocol_config] || %{},
      order: attrs[:order],
      created_at: attrs[:created_at] || attrs[:inserted_at],
      updated_at: attrs[:updated_at]
    }
  end

  # ===========================================================================
  # Predicates
  # ===========================================================================

  @doc """
  Returns true if this protocol handles read direction.
  """
  @spec handles_read?(t()) :: boolean()
  def handles_read?(%__MODULE__{protocol_direction: dir}) do
    DataDirection.handles_read?(dir)
  end

  @doc """
  Returns true if this protocol handles write direction.
  """
  @spec handles_write?(t()) :: boolean()
  def handles_write?(%__MODULE__{protocol_direction: dir}) do
    DataDirection.handles_write?(dir)
  end

  @doc """
  Returns true if this protocol performs CRC operations.
  """
  @spec handles_crc?(t()) :: boolean()
  def handles_crc?(%__MODULE__{protocol_type: type}) do
    ProtocolType.handles_crc?(type)
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp validate_required(attrs) do
    cond do
      is_nil(attrs[:interface_id]) -> {:error, :interface_id_required}
      is_nil(attrs[:protocol_type]) -> {:error, :protocol_type_required}
      is_nil(attrs[:order]) -> {:error, :order_required}
      true -> :ok
    end
  end

  defp parse_protocol_type(type) when is_atom(type) do
    case ProtocolType.validate(type) do
      :ok -> {:ok, type}
      error -> error
    end
  end

  defp parse_protocol_type(type) when is_binary(type) do
    ProtocolType.parse(type)
  end

  defp parse_protocol_type(_), do: {:error, :invalid_protocol_type}

  defp parse_direction(nil), do: {:ok, DataDirection.default()}

  defp parse_direction(dir) when is_atom(dir) do
    case DataDirection.validate(dir) do
      :ok -> {:ok, dir}
      error -> error
    end
  end

  defp parse_direction(dir) when is_binary(dir) do
    DataDirection.parse(dir)
  end

  defp parse_direction(_), do: {:error, :invalid_data_direction}

  defp maybe_parse_direction(nil, current), do: {:ok, current}
  defp maybe_parse_direction(dir, _current), do: parse_direction(dir)

  defp validate_order(order) when is_integer(order) and order >= 0, do: :ok
  defp validate_order(_), do: {:error, :invalid_order}

  defp maybe_validate_order(nil, current), do: {:ok, current}

  defp maybe_validate_order(order, _current) when is_integer(order) and order >= 0,
    do: {:ok, order}

  defp maybe_validate_order(_, _), do: {:error, :invalid_order}

  defp validate_config(protocol_type, config) do
    ProtocolType.validate_config(protocol_type, config)
  end

  defp parse_type_from_persistence(type) when is_atom(type), do: type

  defp parse_type_from_persistence(type) when is_binary(type) do
    case ProtocolType.parse(type) do
      {:ok, parsed} -> parsed
      _ -> :template
    end
  end

  defp parse_type_from_persistence(_), do: :template

  defp parse_direction_from_persistence(dir) when is_atom(dir), do: dir

  defp parse_direction_from_persistence(dir) when is_binary(dir) do
    case DataDirection.parse(dir) do
      {:ok, parsed} -> parsed
      _ -> :read_write
    end
  end

  defp parse_direction_from_persistence(_), do: :read_write
end
