defmodule CCSDS.Time.CDS do
  @moduledoc """
  Exact value representation for CCSDS 301.0-B-4 CDS time.
  """

  import Bitwise

  alias CCSDS.Time.CDS.Configuration
  alias CCSDS.Time.Math

  @type t :: %__MODULE__{
          day_count: non_neg_integer(),
          milliseconds_of_day: non_neg_integer(),
          submilliseconds: non_neg_integer(),
          configuration: Configuration.t()
        }

  defstruct day_count: 0,
            milliseconds_of_day: 0,
            submilliseconds: 0,
            configuration: nil

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = Map.new(attrs)
    known = Map.keys(Map.from_struct(%__MODULE__{}))

    with [] <- Map.keys(attrs) -- known,
         value = struct(__MODULE__, attrs),
         :ok <- validate(value) do
      {:ok, value}
    else
      [_unknown | _rest] -> {:error, :unknown_cds_attribute}
      {:error, _reason} = error -> error
    end
  end

  @spec new!(map() | keyword()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, value} -> value
      {:error, reason} -> raise ArgumentError, "invalid CDS value: #{inspect(reason)}"
    end
  end

  @spec validate(t()) :: :ok | {:error, term()}
  def validate(%__MODULE__{configuration: %Configuration{} = configuration} = value) do
    with :ok <- Configuration.validate(configuration),
         :ok <- validate_day_count(value.day_count, configuration.day_octets),
         :ok <- validate_milliseconds(value.milliseconds_of_day, configuration) do
      validate_submilliseconds(value.submilliseconds, configuration.submillisecond_octets)
    end
  end

  def validate(%__MODULE__{configuration: value}),
    do: {:error, {:invalid_field, :configuration, value}}

  def validate(value), do: {:error, {:invalid_cds, value}}

  @doc "Returns the submillisecond segment as an exact fraction of one millisecond."
  @spec submillisecond_fraction(t()) :: Math.fraction()
  def submillisecond_fraction(%__MODULE__{configuration: %{submillisecond_octets: 0}}),
    do: {0, 1}

  def submillisecond_fraction(%__MODULE__{
        submilliseconds: submilliseconds,
        configuration: %{submillisecond_octets: 2}
      }),
      do: Math.reduce(submilliseconds, 1_000)

  def submillisecond_fraction(%__MODULE__{
        submilliseconds: submilliseconds,
        configuration: %{submillisecond_octets: 4}
      }),
      do: Math.reduce(submilliseconds, 1_000_000_000)

  defp validate_day_count(value, octets)
       when is_integer(value) and value >= 0 and value < 1 <<< (octets * 8),
       do: :ok

  defp validate_day_count(value, octets),
    do: {:error, {:invalid_cds_day_count, value, octets}}

  defp validate_milliseconds(value, configuration)
       when is_integer(value) and value >= 0 do
    maximum = Configuration.maximum_millisecond(configuration)

    if value <= maximum,
      do: :ok,
      else: {:error, {:invalid_cds_milliseconds_of_day, value, maximum}}
  end

  defp validate_milliseconds(value, configuration),
    do:
      {:error,
       {:invalid_cds_milliseconds_of_day, value, Configuration.maximum_millisecond(configuration)}}

  defp validate_submilliseconds(0, 0), do: :ok

  defp validate_submilliseconds(value, 2)
       when is_integer(value) and value >= 0 and value <= 999,
       do: :ok

  defp validate_submilliseconds(value, 4)
       when is_integer(value) and value >= 0 and value <= 999_999_999,
       do: :ok

  defp validate_submilliseconds(value, octets),
    do: {:error, {:invalid_cds_submilliseconds, value, octets}}
end
