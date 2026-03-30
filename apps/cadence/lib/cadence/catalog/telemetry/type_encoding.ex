defmodule Cadence.Catalog.Telemetry.TypeEncoding do
  @moduledoc """
  Canonical binary encoding information for a telemetry type.
  """

  alias Cadence.Catalog.Telemetry.Normalize

  @type encoding_type :: :integer | :float | :string | :binary | :boolean | :time
  @type byte_order :: :big_endian | :little_endian
  @type integer_encoding :: :unsigned | :twos_complement | :sign_magnitude | :ones_complement
  @type float_encoding :: :ieee754 | :mil_std_1750a
  @type string_termination :: :null | :fixed_length | :length_prefixed

  @type t :: %__MODULE__{
          encoding_type: encoding_type() | nil,
          size_bits: pos_integer() | nil,
          byte_order: byte_order(),
          signed: boolean(),
          integer_encoding: integer_encoding(),
          float_encoding: float_encoding() | nil,
          charset: binary() | nil,
          string_termination: string_termination() | nil,
          string_length_prefix_bits: pos_integer() | nil,
          dynamic_size_ref: binary() | nil,
          dynamic_size_adjustment: map()
        }

  defstruct [
    :encoding_type,
    :size_bits,
    :float_encoding,
    :charset,
    :string_termination,
    :string_length_prefix_bits,
    :dynamic_size_ref,
    byte_order: :big_endian,
    signed: false,
    integer_encoding: :unsigned,
    dynamic_size_adjustment: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      encoding_type: Normalize.get(attrs, :encoding_type) |> normalize_encoding_type(),
      size_bits: Normalize.get(attrs, :size_bits),
      byte_order: Normalize.get(attrs, :byte_order, :big_endian) |> normalize_byte_order(),
      signed: Normalize.get(attrs, :signed, false),
      integer_encoding:
        Normalize.get(attrs, :integer_encoding, :unsigned) |> normalize_integer_encoding(),
      float_encoding: Normalize.get(attrs, :float_encoding) |> normalize_float_encoding(),
      charset: Normalize.get(attrs, :charset),
      string_termination:
        Normalize.get(attrs, :string_termination) |> normalize_string_termination(),
      string_length_prefix_bits: Normalize.get(attrs, :string_length_prefix_bits),
      dynamic_size_ref: Normalize.get(attrs, :dynamic_size_ref),
      dynamic_size_adjustment: Normalize.get(attrs, :dynamic_size_adjustment, %{})
    }
  end

  defp normalize_encoding_type(nil), do: nil
  defp normalize_encoding_type(:integer), do: :integer
  defp normalize_encoding_type("integer"), do: :integer
  defp normalize_encoding_type(:float), do: :float
  defp normalize_encoding_type("float"), do: :float
  defp normalize_encoding_type(:string), do: :string
  defp normalize_encoding_type("string"), do: :string
  defp normalize_encoding_type(:binary), do: :binary
  defp normalize_encoding_type("binary"), do: :binary
  defp normalize_encoding_type(:boolean), do: :boolean
  defp normalize_encoding_type("boolean"), do: :boolean
  defp normalize_encoding_type(:time), do: :time
  defp normalize_encoding_type("time"), do: :time
  defp normalize_encoding_type(_other), do: nil

  defp normalize_byte_order(:big_endian), do: :big_endian
  defp normalize_byte_order("big_endian"), do: :big_endian
  defp normalize_byte_order(:little_endian), do: :little_endian
  defp normalize_byte_order("little_endian"), do: :little_endian
  defp normalize_byte_order(_other), do: :big_endian

  defp normalize_integer_encoding(:unsigned), do: :unsigned
  defp normalize_integer_encoding("unsigned"), do: :unsigned
  defp normalize_integer_encoding(:twos_complement), do: :twos_complement
  defp normalize_integer_encoding("twos_complement"), do: :twos_complement
  defp normalize_integer_encoding(:sign_magnitude), do: :sign_magnitude
  defp normalize_integer_encoding("sign_magnitude"), do: :sign_magnitude
  defp normalize_integer_encoding(:ones_complement), do: :ones_complement
  defp normalize_integer_encoding("ones_complement"), do: :ones_complement
  defp normalize_integer_encoding(_other), do: :unsigned

  defp normalize_float_encoding(nil), do: nil
  defp normalize_float_encoding(:ieee754), do: :ieee754
  defp normalize_float_encoding("ieee754"), do: :ieee754
  defp normalize_float_encoding(:mil_std_1750a), do: :mil_std_1750a
  defp normalize_float_encoding("mil_std_1750a"), do: :mil_std_1750a
  defp normalize_float_encoding(_other), do: nil

  defp normalize_string_termination(nil), do: nil
  defp normalize_string_termination(:null), do: :null
  defp normalize_string_termination("null"), do: :null
  defp normalize_string_termination(:fixed_length), do: :fixed_length
  defp normalize_string_termination("fixed_length"), do: :fixed_length
  defp normalize_string_termination(:length_prefixed), do: :length_prefixed
  defp normalize_string_termination("length_prefixed"), do: :length_prefixed
  defp normalize_string_termination(_other), do: nil
end
