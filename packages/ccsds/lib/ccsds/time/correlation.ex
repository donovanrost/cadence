defmodule CCSDS.Time.Correlation do
  @moduledoc """
  Explicit correlation helpers for CUC and CDS values.

  CUC conversion requires a caller-supplied counter/`DateTime` anchor because
  the wire code does not carry a time scale, an agency epoch, or leap-second
  history. CDS conversion uses its UTC day structure; an agency epoch must
  still be supplied explicitly. Every lossy conversion reports its exact
  quantization error.
  """

  alias CCSDS.Time.{CDS, CUC, Math}
  alias CCSDS.Time.CDS.Configuration, as: CDSConfiguration
  alias CCSDS.Time.CUC.Configuration, as: CUCConfiguration

  @ccsds_epoch_date ~D[1958-01-01]
  @microseconds_per_second 1_000_000
  @microseconds_per_millisecond 1_000
  @normal_day_milliseconds 86_400_000

  @spec cuc_to_datetime(CUC.t(), CUC.t(), DateTime.t(), keyword()) ::
          {:ok, DateTime.t(), map()} | {:error, term()}
  def cuc_to_datetime(value, reference_value, reference_datetime, opts \\ [])

  def cuc_to_datetime(
        %CUC{} = value,
        %CUC{} = reference_value,
        %DateTime{} = reference_datetime,
        opts
      )
      when is_list(opts) do
    rounding = Keyword.get(opts, :rounding, :nearest)

    with :ok <- CUC.validate(value),
         :ok <- CUC.validate(reference_value),
         true <- CUC.compatible?(value, reference_value),
         :ok <- validate_rounding(rounding) do
      exact_seconds =
        Math.subtract(CUC.elapsed_fraction(value), CUC.elapsed_fraction(reference_value))

      exact_microseconds = Math.multiply(exact_seconds, @microseconds_per_second)
      rounded_microseconds = Math.round(exact_microseconds, rounding)

      {:ok, DateTime.add(reference_datetime, rounded_microseconds, :microsecond),
       quantization_evidence(exact_microseconds, rounded_microseconds, :microseconds, rounding)}
    else
      false -> {:error, :incompatible_cuc_correlation}
      {:error, _reason} = error -> error
    end
  end

  @spec datetime_to_cuc(
          DateTime.t(),
          CUCConfiguration.t(),
          CUC.t(),
          DateTime.t(),
          keyword()
        ) :: {:ok, CUC.t(), map()} | {:error, term()}
  def datetime_to_cuc(
        %DateTime{} = datetime,
        %CUCConfiguration{} = configuration,
        %CUC{} = reference_value,
        %DateTime{} = reference_datetime,
        opts \\ []
      )
      when is_list(opts) do
    rounding = Keyword.get(opts, :rounding, :nearest)

    with :ok <- CUCConfiguration.validate(configuration),
         :ok <- CUC.validate(reference_value),
         :ok <- validate_cuc_configuration_compatibility(configuration, reference_value),
         :ok <- validate_rounding(rounding) do
      delta_microseconds = DateTime.diff(datetime, reference_datetime, :microsecond)

      elapsed =
        Math.add(
          CUC.elapsed_fraction(reference_value),
          Math.reduce(delta_microseconds, @microseconds_per_second)
        )

      case CUC.from_elapsed_fraction(elapsed, configuration, rounding) do
        {:ok, value, evidence} ->
          {:ok, value,
           Map.merge(evidence, %{
             reference_datetime: reference_datetime,
             delta_microseconds: delta_microseconds
           })}

        {:error, _reason} = error ->
          error
      end
    end
  end

  @spec cds_to_datetime(CDS.t(), keyword()) ::
          {:ok, DateTime.t(), map()} | {:error, term()}
  def cds_to_datetime(%CDS{} = value, opts \\ []) when is_list(opts) do
    rounding = Keyword.get(opts, :rounding, :nearest)

    with :ok <- CDS.validate(value),
         :ok <- validate_rounding(rounding),
         {:ok, epoch_date} <- epoch_date(value.configuration, opts),
         :ok <- validate_datetime_representable(value),
         {:ok, date} <- add_days(epoch_date, value.day_count),
         {:ok, midnight} <- DateTime.new(date, ~T[00:00:00], "Etc/UTC"),
         exact_microseconds = cds_microseconds(value),
         rounded_microseconds = Math.round(exact_microseconds, rounding),
         :ok <- validate_rounded_datetime(value, rounded_microseconds) do
      {:ok, DateTime.add(midnight, rounded_microseconds, :microsecond),
       quantization_evidence(exact_microseconds, rounded_microseconds, :microseconds, rounding)}
    end
  end

  @spec datetime_to_cds(DateTime.t(), CDSConfiguration.t(), keyword()) ::
          {:ok, CDS.t(), map()} | {:error, term()}
  def datetime_to_cds(
        %DateTime{} = datetime,
        %CDSConfiguration{} = configuration,
        opts \\ []
      )
      when is_list(opts) do
    rounding = Keyword.get(opts, :rounding, :nearest)

    with :ok <- CDSConfiguration.validate(configuration),
         :ok <- validate_rounding(rounding),
         :ok <- validate_utc(datetime),
         {:ok, epoch_date} <- epoch_date(configuration, opts),
         {:ok, day_count} <- day_count(datetime, epoch_date),
         {:ok, fields, evidence} <- time_fields(datetime, configuration, rounding),
         {:ok, value} <-
           CDS.new(
             day_count: day_count + fields.day_carry,
             milliseconds_of_day: fields.milliseconds,
             submilliseconds: fields.submilliseconds,
             configuration: configuration
           ) do
      {:ok, value, evidence}
    end
  end

  defp validate_cuc_configuration_compatibility(configuration, reference_value) do
    reference = reference_value.configuration

    if configuration.epoch == reference.epoch and
         configuration.basic_unit == reference.basic_unit,
       do: :ok,
       else: {:error, :incompatible_cuc_correlation}
  end

  defp validate_datetime_representable(%CDS{milliseconds_of_day: milliseconds})
       when milliseconds < @normal_day_milliseconds,
       do: :ok

  defp validate_datetime_representable(_value),
    do: {:error, :cds_leap_second_not_representable_as_datetime}

  defp validate_rounded_datetime(
         %CDS{configuration: %{day_length: day_length}},
         rounded_microseconds
       )
       when day_length in [:positive_leap, :unknown] and
              rounded_microseconds >= @normal_day_milliseconds * @microseconds_per_millisecond,
       do: {:error, :cds_rounding_enters_unrepresentable_leap_second}

  defp validate_rounded_datetime(_value, _rounded_microseconds), do: :ok

  defp epoch_date(%{epoch: :ccsds}, opts) do
    case Keyword.get(opts, :epoch_date, @ccsds_epoch_date) do
      @ccsds_epoch_date -> {:ok, @ccsds_epoch_date}
      value -> {:error, {:ccsds_epoch_date_mismatch, value}}
    end
  end

  defp epoch_date(%{epoch: :agency}, opts) do
    case Keyword.fetch(opts, :epoch_date) do
      {:ok, %Date{} = date} -> {:ok, date}
      {:ok, value} -> {:error, {:invalid_agency_epoch_date, value}}
      :error -> {:error, :agency_epoch_date_required}
    end
  end

  defp add_days(epoch, days) do
    {:ok, Date.add(epoch, days)}
  rescue
    ArgumentError -> {:error, {:cds_date_out_of_range, epoch, days}}
  end

  defp cds_microseconds(%CDS{configuration: %{submillisecond_octets: 0}} = value),
    do: {value.milliseconds_of_day * @microseconds_per_millisecond, 1}

  defp cds_microseconds(%CDS{configuration: %{submillisecond_octets: 2}} = value) do
    {value.milliseconds_of_day * @microseconds_per_millisecond + value.submilliseconds, 1}
  end

  defp cds_microseconds(%CDS{configuration: %{submillisecond_octets: 4}} = value) do
    Math.reduce(
      value.milliseconds_of_day * @microseconds_per_millisecond * 1_000_000 +
        value.submilliseconds,
      1_000_000
    )
  end

  defp day_count(datetime, epoch_date) do
    days = Date.diff(DateTime.to_date(datetime), epoch_date)
    if days >= 0, do: {:ok, days}, else: {:error, :datetime_precedes_cds_epoch}
  end

  defp time_fields(datetime, %{submillisecond_octets: 0}, rounding) do
    microseconds = microseconds_after_midnight(datetime)
    exact_milliseconds = Math.reduce(microseconds, @microseconds_per_millisecond)
    milliseconds = Math.round(exact_milliseconds, rounding)
    {day_carry, milliseconds} = normalize_milliseconds(milliseconds)

    evidence =
      quantization_evidence(
        {microseconds, 1},
        (day_carry * @normal_day_milliseconds + milliseconds) *
          @microseconds_per_millisecond,
        :microseconds,
        rounding
      )

    {:ok, %{day_carry: day_carry, milliseconds: milliseconds, submilliseconds: 0}, evidence}
  end

  defp time_fields(datetime, %{submillisecond_octets: 2}, rounding) do
    microseconds = microseconds_after_midnight(datetime)
    milliseconds = div(microseconds, @microseconds_per_millisecond)
    submilliseconds = rem(microseconds, @microseconds_per_millisecond)
    evidence = quantization_evidence({microseconds, 1}, microseconds, :microseconds, rounding)

    {:ok, %{day_carry: 0, milliseconds: milliseconds, submilliseconds: submilliseconds}, evidence}
  end

  defp time_fields(datetime, %{submillisecond_octets: 4}, rounding) do
    microseconds = microseconds_after_midnight(datetime)
    milliseconds = div(microseconds, @microseconds_per_millisecond)
    microseconds_of_millisecond = rem(microseconds, @microseconds_per_millisecond)
    submilliseconds = microseconds_of_millisecond * 1_000_000
    evidence = quantization_evidence({microseconds, 1}, microseconds, :microseconds, rounding)

    {:ok, %{day_carry: 0, milliseconds: milliseconds, submilliseconds: submilliseconds}, evidence}
  end

  defp normalize_milliseconds(@normal_day_milliseconds), do: {1, 0}
  defp normalize_milliseconds(milliseconds), do: {0, milliseconds}

  defp microseconds_after_midnight(datetime) do
    time = DateTime.to_time(datetime)
    seconds = time.hour * 3_600 + time.minute * 60 + time.second
    seconds * @microseconds_per_second + elem(time.microsecond, 0)
  end

  defp validate_utc(%DateTime{utc_offset: utc_offset, std_offset: std_offset})
       when utc_offset + std_offset == 0,
       do: :ok

  defp validate_utc(datetime), do: {:error, {:cds_datetime_must_be_utc, datetime.time_zone}}

  defp validate_rounding(rounding)
       when rounding in [:floor, :ceiling, :nearest, :toward_zero],
       do: :ok

  defp validate_rounding(rounding), do: {:error, {:invalid_rounding, rounding}}

  defp quantization_evidence(exact, rounded, unit, rounding) do
    %{
      exact: exact,
      rounded: rounded,
      error: Math.quantization_error(exact, rounded),
      unit: unit,
      rounding: rounding
    }
  end
end
