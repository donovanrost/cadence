defmodule Cadence.CCSDS.CFDP.Configuration do
  @moduledoc """
  Managed parameters used by the dependency-free CFDP codecs and transaction
  procedures.

  Entity and transaction-sequence widths control generation only. Decoding
  accepts every width allowed by CCSDS 727.0-B-5 and preserves the received
  widths on the semantic PDU.
  """

  @type identifier_width :: :adaptive | 1..8
  @type t :: %__MODULE__{
          entity_id_octets: identifier_width(),
          sequence_number_octets: identifier_width(),
          maximum_pdu_data_octets: 1..0xFFFF,
          maximum_file_segment_octets: pos_integer(),
          valid_checksum_types: [0..15]
        }

  defstruct entity_id_octets: :adaptive,
            sequence_number_octets: :adaptive,
            maximum_pdu_data_octets: 0xFFFF,
            maximum_file_segment_octets: 1_024,
            valid_checksum_types: [0, 15]

  @known_fields [
    :entity_id_octets,
    :sequence_number_octets,
    :maximum_pdu_data_octets,
    :maximum_file_segment_octets,
    :valid_checksum_types
  ]

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs \\ %{}) when is_map(attrs) or is_list(attrs) do
    attrs = Map.new(attrs)

    case Map.keys(attrs) -- @known_fields do
      [] ->
        configuration = struct(__MODULE__, attrs)

        case validate(configuration) do
          :ok -> {:ok, configuration}
          {:error, _reason} = error -> error
        end

      _unknown ->
        {:error, :unknown_cfdp_configuration_attribute}
    end
  end

  @spec new!(map() | keyword()) :: t()
  def new!(attrs \\ %{}) do
    case new(attrs) do
      {:ok, configuration} ->
        configuration

      {:error, reason} ->
        raise ArgumentError, "invalid CFDP configuration: #{inspect(reason)}"
    end
  end

  @spec validate(t()) :: :ok | {:error, term()}
  def validate(%__MODULE__{} = configuration) do
    with :ok <- validate_width(configuration.entity_id_octets, :entity_id_octets),
         :ok <- validate_width(configuration.sequence_number_octets, :sequence_number_octets),
         :ok <-
           validate_range(
             configuration.maximum_pdu_data_octets,
             1,
             0xFFFF,
             :maximum_pdu_data_octets
           ),
         :ok <-
           validate_positive(
             configuration.maximum_file_segment_octets,
             :maximum_file_segment_octets
           ) do
      validate_checksum_types(configuration.valid_checksum_types)
    end
  end

  def validate(value), do: {:error, {:invalid_cfdp_configuration, value}}

  defp validate_width(:adaptive, _field), do: :ok
  defp validate_width(value, _field) when value in 1..8, do: :ok
  defp validate_width(value, field), do: {:error, {:invalid_field, field, value}}

  defp validate_positive(value, _field) when is_integer(value) and value > 0, do: :ok
  defp validate_positive(value, field), do: {:error, {:invalid_field, field, value}}

  defp validate_range(value, minimum, maximum, _field)
       when is_integer(value) and value >= minimum and value <= maximum,
       do: :ok

  defp validate_range(value, _minimum, _maximum, field),
    do: {:error, {:invalid_field, field, value}}

  defp validate_checksum_types(values) when is_list(values) do
    cond do
      values == [] ->
        {:error, {:invalid_field, :valid_checksum_types, values}}

      Enum.any?(values, &(!is_integer(&1) or &1 < 0 or &1 > 15)) ->
        {:error, {:invalid_field, :valid_checksum_types, values}}

      length(values) != length(Enum.uniq(values)) ->
        {:error, {:duplicate_field_value, :valid_checksum_types}}

      true ->
        :ok
    end
  end

  defp validate_checksum_types(value),
    do: {:error, {:invalid_field, :valid_checksum_types, value}}
end
