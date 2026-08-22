defmodule Cadence.CCSDS.EncapsulationPacket.Configuration do
  @moduledoc """
  Managed Encapsulation Packet Protocol parameters for one service provider.

  Receiving always accepts every standard header size. `header_mode` controls
  only generation: `:adaptive` selects the smallest legal header, while a
  fixed size supports mission implementations that keep header size static.
  """

  @maximum_data_unit_octets 4_294_967_287
  @assigned_protocol_ids [0, 1, 2, 3, 4, 6, 7]

  @type header_mode :: :adaptive | 1 | 2 | 4 | 8
  @type t :: %__MODULE__{
          minimum_data_unit_octets: non_neg_integer(),
          maximum_data_unit_octets: non_neg_integer(),
          valid_protocol_ids: [0..7],
          valid_extended_protocol_ids: [0..15],
          header_mode: header_mode()
        }

  defstruct minimum_data_unit_octets: 0,
            maximum_data_unit_octets: @maximum_data_unit_octets,
            valid_protocol_ids: @assigned_protocol_ids,
            valid_extended_protocol_ids: [],
            header_mode: :adaptive

  @known_fields [
    :minimum_data_unit_octets,
    :maximum_data_unit_octets,
    :valid_protocol_ids,
    :valid_extended_protocol_ids,
    :header_mode
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
        {:error, :unknown_encapsulation_configuration_attribute}
    end
  end

  @spec new!(map() | keyword()) :: t()
  def new!(attrs \\ %{}) do
    case new(attrs) do
      {:ok, configuration} ->
        configuration

      {:error, reason} ->
        raise ArgumentError, "invalid Encapsulation Packet configuration: #{inspect(reason)}"
    end
  end

  @spec validate(t()) :: :ok | {:error, term()}
  def validate(%__MODULE__{} = configuration) do
    with :ok <-
           validate_range(
             configuration.minimum_data_unit_octets,
             0,
             @maximum_data_unit_octets,
             :minimum_data_unit_octets
           ),
         :ok <-
           validate_range(
             configuration.maximum_data_unit_octets,
             0,
             @maximum_data_unit_octets,
             :maximum_data_unit_octets
           ),
         true <-
           configuration.minimum_data_unit_octets <= configuration.maximum_data_unit_octets,
         :ok <- validate_set(configuration.valid_protocol_ids, 0, 7, :valid_protocol_ids),
         :ok <-
           validate_set(
             configuration.valid_extended_protocol_ids,
             0,
             15,
             :valid_extended_protocol_ids,
             allow_empty?: true
           ),
         :ok <- validate_header_mode(configuration.header_mode) do
      validate_extended_coverage(configuration)
    else
      false ->
        {:error,
         {:invalid_data_unit_range, configuration.minimum_data_unit_octets,
          configuration.maximum_data_unit_octets}}

      {:error, _reason} = error ->
        error
    end
  end

  def validate(value), do: {:error, {:invalid_encapsulation_configuration, value}}

  @spec maximum_data_unit_octets() :: 4_294_967_287
  def maximum_data_unit_octets, do: @maximum_data_unit_octets

  defp validate_extended_coverage(configuration) do
    if 6 in configuration.valid_protocol_ids or configuration.valid_extended_protocol_ids == [],
      do: :ok,
      else: {:error, :extended_protocol_ids_require_protocol_id_6}
  end

  defp validate_header_mode(value) when value in [:adaptive, 1, 2, 4, 8], do: :ok
  defp validate_header_mode(value), do: {:error, {:invalid_field, :header_mode, value}}

  defp validate_set(values, minimum, maximum, field, opts \\ [])

  defp validate_set(values, minimum, maximum, field, opts) when is_list(values) do
    allow_empty? = Keyword.get(opts, :allow_empty?, false)

    cond do
      values == [] and not allow_empty? ->
        {:error, {:invalid_field, field, values}}

      Enum.any?(values, &(!is_integer(&1) or &1 < minimum or &1 > maximum)) ->
        {:error, {:invalid_field, field, values}}

      length(values) != length(Enum.uniq(values)) ->
        {:error, {:duplicate_field_value, field}}

      true ->
        :ok
    end
  end

  defp validate_set(value, _minimum, _maximum, field, _opts),
    do: {:error, {:invalid_field, field, value}}

  defp validate_range(value, minimum, maximum, _field)
       when is_integer(value) and value >= minimum and value <= maximum,
       do: :ok

  defp validate_range(value, _minimum, _maximum, field),
    do: {:error, {:invalid_field, field, value}}
end
