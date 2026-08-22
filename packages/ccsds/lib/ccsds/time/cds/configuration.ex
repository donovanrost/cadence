defmodule CCSDS.Time.CDS.Configuration do
  @moduledoc """
  Managed metadata for a CCSDS Day Segmented Time Code.

  Leap-second knowledge is external to the wire code. `day_length` can tighten
  validation when the caller has that knowledge; `:unknown` accepts the full
  range permitted by the standard for any normal or adjusted UTC day.
  """

  @type epoch :: :ccsds | :agency
  @type day_length :: :unknown | :normal | :positive_leap | :negative_leap
  @type t :: %__MODULE__{
          epoch: epoch(),
          day_octets: 2 | 3,
          submillisecond_octets: 0 | 2 | 4,
          day_length: day_length()
        }

  defstruct epoch: :ccsds,
            day_octets: 2,
            submillisecond_octets: 0,
            day_length: :unknown

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs \\ %{}) when is_map(attrs) or is_list(attrs) do
    attrs = Map.new(attrs)
    known = Map.keys(Map.from_struct(%__MODULE__{}))

    with [] <- Map.keys(attrs) -- known,
         configuration = struct(__MODULE__, attrs),
         :ok <- validate(configuration) do
      {:ok, configuration}
    else
      [_unknown | _rest] -> {:error, :unknown_cds_configuration_attribute}
      {:error, _reason} = error -> error
    end
  end

  @spec new!(map() | keyword()) :: t()
  def new!(attrs \\ %{}) do
    case new(attrs) do
      {:ok, configuration} -> configuration
      {:error, reason} -> raise ArgumentError, "invalid CDS configuration: #{inspect(reason)}"
    end
  end

  @spec validate(t()) :: :ok | {:error, term()}
  def validate(%__MODULE__{} = configuration) do
    with :ok <- validate_member(configuration.epoch, [:ccsds, :agency], :epoch),
         :ok <- validate_member(configuration.day_octets, [2, 3], :day_octets),
         :ok <-
           validate_member(
             configuration.submillisecond_octets,
             [0, 2, 4],
             :submillisecond_octets
           ) do
      validate_member(
        configuration.day_length,
        [:unknown, :normal, :positive_leap, :negative_leap],
        :day_length
      )
    end
  end

  def validate(value), do: {:error, {:invalid_cds_configuration, value}}

  @spec time_octets(t()) :: 6..11
  def time_octets(%__MODULE__{} = configuration),
    do: configuration.day_octets + 4 + configuration.submillisecond_octets

  @spec maximum_millisecond(t()) :: 86_398_999..86_400_999
  def maximum_millisecond(%__MODULE__{day_length: :negative_leap}), do: 86_398_999
  def maximum_millisecond(%__MODULE__{day_length: :normal}), do: 86_399_999
  def maximum_millisecond(%__MODULE__{}), do: 86_400_999

  defp validate_member(value, allowed, field) do
    if value in allowed, do: :ok, else: {:error, {:invalid_field, field, value}}
  end
end
