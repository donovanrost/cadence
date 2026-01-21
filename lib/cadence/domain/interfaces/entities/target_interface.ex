defmodule Cadence.Domain.Interfaces.Entities.TargetInterface do
  @moduledoc """
  Pure domain entity representing the routing between targets and interfaces.

  Defines which interfaces serve which targets and the direction of data flow:
  - `:read` - Interface receives telemetry from target
  - `:write` - Interface sends commands to target
  - `:read_write` - Bidirectional communication

  ## Usage

      {:ok, routing} = TargetInterface.new(%{
        target_id: "sat-001-uuid",
        interface_id: "tcp-int-1-uuid",
        direction: :read
      })
  """

  alias Cadence.Domain.Interfaces.ValueObjects.DataDirection
  alias Cadence.Time, as: CadenceTime

  @type t :: %__MODULE__{
          id: String.t() | nil,
          target_id: String.t(),
          interface_id: String.t(),
          direction: DataDirection.t(),
          scid: non_neg_integer() | nil,
          tc_stream_id: String.t() | nil,
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @enforce_keys [:target_id, :interface_id, :direction]
  defstruct [
    :id,
    :target_id,
    :interface_id,
    :direction,
    :scid,
    :tc_stream_id,
    :created_at,
    :updated_at
  ]

  @doc """
  Creates a new TargetInterface routing entity.

  ## Attributes

  Required:
  - `:target_id` - ID of the target
  - `:interface_id` - ID of the interface
  - `:direction` - Data direction (:read, :write, :read_write)
  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    with :ok <- validate_required(attrs),
         {:ok, direction} <- parse_direction(attrs[:direction]),
         :ok <- validate_scid(attrs),
         {:ok, tc_stream_id} <- parse_tc_stream_id(attrs) do
      {:ok,
       %__MODULE__{
         id: attrs[:id],
         target_id: attrs[:target_id],
         interface_id: attrs[:interface_id],
         direction: direction,
         scid: Map.get(attrs, :scid),
         tc_stream_id: tc_stream_id,
         created_at: attrs[:created_at],
         updated_at: attrs[:updated_at]
       }}
    end
  end

  @doc """
  Updates the direction of the routing.
  """
  @spec update_direction(t(), DataDirection.t()) :: {:ok, t()} | {:error, term()}
  def update_direction(%__MODULE__{} = routing, new_direction) do
    case parse_direction(new_direction) do
      {:ok, direction} ->
        {:ok, %{routing | direction: direction, updated_at: CadenceTime.now()}}

      error ->
        error
    end
  end

  @doc """
  Reconstructs a routing entity from persisted data.
  """
  @spec from_persistence(map()) :: t()
  def from_persistence(attrs) do
    %__MODULE__{
      id: attrs[:id],
      target_id: attrs[:target_id],
      interface_id: attrs[:interface_id],
      direction: parse_direction_from_persistence(attrs[:direction]),
      scid: attrs[:scid],
      tc_stream_id: normalize_tc_stream_id(attrs[:tc_stream_id], attrs[:target_id]),
      created_at: attrs[:created_at] || attrs[:inserted_at],
      updated_at: attrs[:updated_at]
    }
  end

  # ===========================================================================
  # Predicates
  # ===========================================================================

  @doc """
  Returns true if this routing allows receiving data from the target.
  """
  @spec allows_read?(t()) :: boolean()
  def allows_read?(%__MODULE__{direction: dir}) do
    DataDirection.handles_read?(dir)
  end

  @doc """
  Returns true if this routing allows sending data to the target.
  """
  @spec allows_write?(t()) :: boolean()
  def allows_write?(%__MODULE__{direction: dir}) do
    DataDirection.handles_write?(dir)
  end

  @doc """
  Returns true if this is bidirectional routing.
  """
  @spec bidirectional?(t()) :: boolean()
  def bidirectional?(%__MODULE__{direction: dir}) do
    DataDirection.bidirectional?(dir)
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp validate_required(attrs) do
    cond do
      is_nil(attrs[:target_id]) -> {:error, :target_id_required}
      is_nil(attrs[:interface_id]) -> {:error, :interface_id_required}
      is_nil(attrs[:direction]) -> {:error, :direction_required}
      true -> :ok
    end
  end

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

  defp parse_direction_from_persistence(dir) when is_atom(dir), do: dir

  defp parse_direction_from_persistence(dir) when is_binary(dir) do
    case DataDirection.parse(dir) do
      {:ok, parsed} -> parsed
      _ -> :read_write
    end
  end

  defp parse_direction_from_persistence(_), do: :read_write

  defp validate_scid(attrs) when is_map(attrs) do
    case Map.get(attrs, :scid) do
      nil -> :ok
      scid when is_integer(scid) and scid >= 0 and scid < 1024 -> :ok
      scid -> {:error, {:invalid, :scid, scid}}
    end
  end

  defp parse_tc_stream_id(attrs) when is_map(attrs) do
    stream_id = Map.get(attrs, :tc_stream_id)

    stream_id =
      case normalize_blank(stream_id) do
        nil -> Map.get(attrs, :target_id)
        value when is_integer(value) -> Integer.to_string(value)
        value -> value
      end

    cond do
      is_nil(stream_id) -> {:ok, nil}
      is_binary(stream_id) -> {:ok, stream_id}
      true -> {:error, {:invalid, :tc_stream_id, stream_id}}
    end
  end

  defp normalize_tc_stream_id(nil, target_id), do: target_id
  defp normalize_tc_stream_id("", target_id), do: target_id

  defp normalize_tc_stream_id(value, _target_id) when is_integer(value) do
    Integer.to_string(value)
  end

  defp normalize_tc_stream_id(value, _target_id) when is_binary(value), do: value
  defp normalize_tc_stream_id(_value, _target_id), do: nil

  defp normalize_blank(""), do: nil
  defp normalize_blank(value), do: value
end
