defmodule Cadence.MissionDatabase.DataEncoding do
  @moduledoc """
  Describes how a value is encoded in binary format.

  This captures the wire format for telemetry extraction and command encoding.

  ## Integer Encoding Example

      %DataEncoding{
        encoding_type: :integer,
        size_in_bits: 16,
        byte_order: :big_endian,
        signed: false,
        integer_encoding: :unsigned
      }

  ## Float Encoding Example

      %DataEncoding{
        encoding_type: :float,
        size_in_bits: 32,
        byte_order: :big_endian,
        float_encoding: :ieee754
      }

  ## String Encoding Example

      %DataEncoding{
        encoding_type: :string,
        size_in_bits: 64,
        charset: "UTF-8",
        string_termination: :null
      }

  ## Dynamic Size Example

      %DataEncoding{
        encoding_type: :binary,
        dynamic_size_ref: "HEADER.LENGTH",
        dynamic_size_linear_adjustment: %{slope: 8, intercept: 0}  # LENGTH is in bytes, convert to bits
      }
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :encoding_type, Ecto.Enum, values: [:integer, :float, :string, :binary, :boolean]

    # Bit-level positioning
    field :size_in_bits, :integer
    field :byte_order, Ecto.Enum, values: [:big_endian, :little_endian], default: :big_endian

    # Integer-specific
    field :signed, :boolean, default: false
    field :integer_encoding, Ecto.Enum, values: [
      :unsigned, :twos_complement, :sign_magnitude, :ones_complement
    ], default: :unsigned

    # Float-specific
    field :float_encoding, Ecto.Enum, values: [:ieee754, :mil_std_1750a], default: :ieee754

    # String-specific
    field :charset, :string, default: "UTF-8"
    field :string_termination, Ecto.Enum, values: [:null, :fixed_length, :length_prefixed]
    field :string_length_prefix_bits, :integer

    # Dynamic size (reference to another parameter)
    field :dynamic_size_ref, :string
    # %{slope: float, intercept: float} - actual_bits = slope * ref_value + intercept
    field :dynamic_size_linear_adjustment, :map
  end

  @doc """
  Changeset for creating or updating data encoding.
  """
  def changeset(encoding, attrs) do
    encoding
    |> cast(attrs, [
      :encoding_type,
      :size_in_bits,
      :byte_order,
      :signed,
      :integer_encoding,
      :float_encoding,
      :charset,
      :string_termination,
      :string_length_prefix_bits,
      :dynamic_size_ref,
      :dynamic_size_linear_adjustment
    ])
    |> validate_required([:encoding_type])
    |> validate_size_or_dynamic()
    |> validate_type_specific_fields()
  end

  defp validate_size_or_dynamic(changeset) do
    size = get_field(changeset, :size_in_bits)
    dynamic = get_field(changeset, :dynamic_size_ref)

    if is_nil(size) and is_nil(dynamic) do
      add_error(changeset, :size_in_bits, "must specify size_in_bits or dynamic_size_ref")
    else
      changeset
    end
  end

  defp validate_type_specific_fields(changeset) do
    case get_field(changeset, :encoding_type) do
      :string ->
        validate_string_encoding(changeset)

      :integer ->
        validate_integer_encoding(changeset)

      _ ->
        changeset
    end
  end

  defp validate_string_encoding(changeset) do
    termination = get_field(changeset, :string_termination)
    prefix_bits = get_field(changeset, :string_length_prefix_bits)

    case termination do
      :length_prefixed when is_nil(prefix_bits) ->
        add_error(changeset, :string_length_prefix_bits, "required when string_termination is :length_prefixed")

      _ ->
        changeset
    end
  end

  defp validate_integer_encoding(changeset) do
    signed = get_field(changeset, :signed)
    encoding = get_field(changeset, :integer_encoding)

    if signed and encoding == :unsigned do
      add_error(changeset, :integer_encoding, "cannot be :unsigned when signed is true")
    else
      changeset
    end
  end
end
