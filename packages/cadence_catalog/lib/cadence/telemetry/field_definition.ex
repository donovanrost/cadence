defmodule Cadence.Telemetry.FieldDefinition do
  @moduledoc """
  Definition of one field inside a telemetry packet data payload.
  """

  alias Cadence.Catalog.Ids

  @type data_type :: :uint | :int | :bool | :float | :binary | :string
  @type byte_order :: :big_endian | :little_endian

  @typedoc """
  A field's calibrator (mission-model telemetry contract 3): a polynomial over the raw value,
  coefficients lowest order first. `nil`: the engineering value is the raw value.
  """
  @type calibrator :: %{type: :polynomial, coefficients: [number()]} | nil

  @typedoc "The field's defined states (raw integer value and label), from its parameter type."
  @type enumeration :: %{value: integer(), label: binary()}

  @type t :: %__MODULE__{
          field_id: binary(),
          parameter_id: binary() | nil,
          qualified_name: binary() | nil,
          name: binary(),
          offset_bits: non_neg_integer(),
          size_bits: pos_integer(),
          data_type: data_type(),
          byte_order: byte_order(),
          engineering_unit: binary() | nil,
          calibrator: calibrator(),
          enumerations: [enumeration()]
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
    :calibrator,
    byte_order: :big_endian,
    enumerations: []
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
      engineering_unit: Map.get(attrs, :engineering_unit),
      calibrator: attrs |> Map.get(:calibrator) |> normalize_calibrator(),
      enumerations: attrs |> Map.get(:enumerations, []) |> normalize_enumerations()
    }
  end

  # Plans are stored as JSON documents, so keys and the type arrive as strings there.
  defp normalize_calibrator(nil), do: nil

  defp normalize_calibrator(calibrator) when is_map(calibrator) do
    with type when type in [:polynomial, "polynomial"] <- field(calibrator, :type),
         coefficients when is_list(coefficients) and coefficients != [] <-
           field(calibrator, :coefficients),
         true <- Enum.all?(coefficients, &is_number/1) do
      %{type: :polynomial, coefficients: coefficients}
    else
      _other -> raise ArgumentError, "unsupported telemetry calibrator: #{inspect(calibrator)}"
    end
  end

  defp normalize_enumerations(nil), do: []

  defp normalize_enumerations(enumerations) when is_list(enumerations) do
    Enum.map(enumerations, fn enumeration ->
      case {field(enumeration, :value), field(enumeration, :label)} do
        {value, label} when is_integer(value) and is_binary(label) ->
          %{value: value, label: label}

        _other ->
          raise ArgumentError, "invalid telemetry enumeration: #{inspect(enumeration)}"
      end
    end)
  end

  defp field(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

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
