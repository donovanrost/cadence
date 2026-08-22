defmodule CCSDS.Time.CUC.Configuration do
  @moduledoc """
  Managed metadata for a CCSDS Unsegmented Time Code.

  The P-field carries the epoch class and counter lengths, but not an actual
  agency epoch or arbitrary basic time unit. `basic_unit` is therefore an exact
  fraction of one SI second supplied by the caller.
  """

  @type epoch :: :ccsds | :agency
  @type basic_unit :: {pos_integer(), pos_integer()}
  @type t :: %__MODULE__{
          epoch: epoch(),
          coarse_octets: 1..7,
          fine_octets: 0..10,
          basic_unit: basic_unit(),
          mission_bits: 0..3
        }

  defstruct epoch: :ccsds,
            coarse_octets: 4,
            fine_octets: 0,
            basic_unit: {1, 1},
            mission_bits: 0

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs \\ %{}) when is_map(attrs) or is_list(attrs) do
    attrs = Map.new(attrs)
    known = Map.keys(Map.from_struct(%__MODULE__{}))

    with [] <- Map.keys(attrs) -- known,
         configuration = struct(__MODULE__, attrs),
         {:ok, configuration} <- normalize_basic_unit(configuration),
         :ok <- validate(configuration) do
      {:ok, configuration}
    else
      [_unknown | _rest] -> {:error, :unknown_cuc_configuration_attribute}
      {:error, _reason} = error -> error
    end
  end

  @spec new!(map() | keyword()) :: t()
  def new!(attrs \\ %{}) do
    case new(attrs) do
      {:ok, configuration} -> configuration
      {:error, reason} -> raise ArgumentError, "invalid CUC configuration: #{inspect(reason)}"
    end
  end

  @spec validate(t()) :: :ok | {:error, term()}
  def validate(%__MODULE__{} = configuration) do
    with :ok <- validate_member(configuration.epoch, [:ccsds, :agency], :epoch),
         :ok <- validate_range(configuration.coarse_octets, 1, 7, :coarse_octets),
         :ok <- validate_range(configuration.fine_octets, 0, 10, :fine_octets),
         :ok <- validate_basic_unit(configuration.basic_unit) do
      validate_range(configuration.mission_bits, 0, 3, :mission_bits)
    end
  end

  def validate(value), do: {:error, {:invalid_cuc_configuration, value}}

  @spec time_octets(t()) :: pos_integer()
  def time_octets(%__MODULE__{} = configuration),
    do: configuration.coarse_octets + configuration.fine_octets

  defp normalize_basic_unit(%__MODULE__{basic_unit: {numerator, denominator}} = configuration)
       when is_integer(numerator) and numerator > 0 and is_integer(denominator) and
              denominator > 0 do
    divisor = Integer.gcd(numerator, denominator)
    {:ok, %{configuration | basic_unit: {div(numerator, divisor), div(denominator, divisor)}}}
  end

  defp normalize_basic_unit(configuration), do: {:ok, configuration}

  defp validate_basic_unit({numerator, denominator})
       when is_integer(numerator) and numerator > 0 and is_integer(denominator) and
              denominator > 0,
       do: :ok

  defp validate_basic_unit(value), do: {:error, {:invalid_field, :basic_unit, value}}

  defp validate_member(value, allowed, field) do
    if value in allowed, do: :ok, else: {:error, {:invalid_field, field, value}}
  end

  defp validate_range(value, minimum, maximum, _field)
       when is_integer(value) and value >= minimum and value <= maximum,
       do: :ok

  defp validate_range(value, _minimum, _maximum, field),
    do: {:error, {:invalid_field, field, value}}
end
