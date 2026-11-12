defmodule Cadence.Telemetry.FieldDefinition do
  @moduledoc """
  Definition of one field inside a telemetry packet data payload.
  """

  alias Cadence.Catalog.Ids

  @type data_type :: :uint | :int | :bool | :float | :binary | :string
  @type byte_order :: :big_endian | :little_endian

  @type t :: %__MODULE__{
          field_id: binary(),
          parameter_id: binary() | nil,
          qualified_name: binary() | nil,
          name: binary(),
          offset_bits: non_neg_integer(),
          size_bits: pos_integer(),
          data_type: data_type(),
          byte_order: byte_order(),
          engineering_unit: binary() | nil
        }

  defstruct [
    :field_id,
    :parameter_id,
    :qualified_name,
    :name,
    :offset_bits,
    :size_bits,
    :data_type,
    :engineering_unit,
    byte_order: :big_endian
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      field_id: Map.get(attrs, :field_id, Ids.new("field")),
      parameter_id: Map.get(attrs, :parameter_id),
      qualified_name: Map.get(attrs, :qualified_name),
      name: Map.fetch!(attrs, :name),
      offset_bits: Map.get(attrs, :offset_bits, 0),
      size_bits: Map.fetch!(attrs, :size_bits),
      data_type:
        attrs
        |> Map.get(:data_type, :uint)
        |> normalize_data_type(),
      byte_order:
        attrs
        |> Map.get(:byte_order, :big_endian)
        |> normalize_byte_order(),
      engineering_unit: Map.get(attrs, :engineering_unit)
    }
  end

  defp normalize_data_type(data_type) when is_atom(data_type), do: data_type

  # An explicit list, not the atom table (2026-11-12 sweep): stored definitions decode in any VM.
  @data_types_by_name Map.new(~w(uint int bool float binary string)a, &{Atom.to_string(&1), &1})

  defp normalize_data_type(data_type) when is_binary(data_type) do
    case Map.fetch(@data_types_by_name, data_type) do
      {:ok, atom} -> atom
      :error -> raise ArgumentError, "unknown telemetry field data_type: #{inspect(data_type)}"
    end
  end

  defp normalize_byte_order(:big_endian), do: :big_endian
  defp normalize_byte_order("big_endian"), do: :big_endian
  defp normalize_byte_order(:little_endian), do: :little_endian
  defp normalize_byte_order("little_endian"), do: :little_endian
  defp normalize_byte_order(_other), do: :big_endian
end
