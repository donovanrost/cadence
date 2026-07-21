defmodule Cadence.CCSDS.TimeCorrelationTest do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.Time.{CDS, Correlation, CUC}
  alias Cadence.CCSDS.Time.CDS.Configuration, as: CDSConfiguration
  alias Cadence.CCSDS.Time.CUC.Configuration, as: CUCConfiguration

  test "correlates CUC using an explicit counter and DateTime anchor" do
    configuration = CUCConfiguration.new!(coarse_octets: 4, fine_octets: 3)
    reference = CUC.new!(coarse_time: 10, fine_time: 0, configuration: configuration)

    value =
      CUC.new!(
        coarse_time: 11,
        fine_time: 0x800000,
        configuration: configuration
      )

    reference_datetime = ~U[2026-07-20 12:00:00.000000Z]

    assert {:ok, ~U[2026-07-20 12:00:01.500000Z], evidence} =
             Correlation.cuc_to_datetime(value, reference, reference_datetime)

    assert evidence.error == {0, 1}

    target_configuration = CUCConfiguration.new!(coarse_octets: 4, fine_octets: 1)
    datetime = ~U[2026-07-20 12:00:02.250000Z]

    assert {:ok, correlated, inverse_evidence} =
             Correlation.datetime_to_cuc(
               datetime,
               target_configuration,
               reference,
               reference_datetime
             )

    assert correlated.coarse_time == 12
    assert correlated.fine_time == 64
    assert inverse_evidence.error_seconds == {0, 1}
  end

  test "rejects CUC correlation across different epoch classes or units" do
    ccsds_configuration = CUCConfiguration.new!()
    agency_configuration = CUCConfiguration.new!(epoch: :agency)
    ccsds = CUC.new!(coarse_time: 0, fine_time: 0, configuration: ccsds_configuration)
    agency = CUC.new!(coarse_time: 0, fine_time: 0, configuration: agency_configuration)

    assert {:error, :incompatible_cuc_correlation} =
             Correlation.cuc_to_datetime(ccsds, agency, ~U[2026-07-20 00:00:00Z])
  end

  test "converts CDS microsecond time against the CCSDS UTC epoch" do
    configuration = CDSConfiguration.new!(submillisecond_octets: 2, day_length: :normal)

    value =
      CDS.new!(
        day_count: 1,
        milliseconds_of_day: 3_723_004,
        submilliseconds: 500,
        configuration: configuration
      )

    expected = ~U[1958-01-02 01:02:03.004500Z]
    assert {:ok, ^expected, evidence} = Correlation.cds_to_datetime(value)
    assert evidence.error == {0, 1}

    assert {:ok, ^value, inverse_evidence} =
             Correlation.datetime_to_cds(expected, configuration)

    assert inverse_evidence.error == {0, 1}
  end

  test "reports picosecond rounding and refuses to hide a leap second" do
    picosecond_configuration =
      CDSConfiguration.new!(submillisecond_octets: 4, day_length: :normal)

    picosecond =
      CDS.new!(
        day_count: 0,
        milliseconds_of_day: 0,
        submilliseconds: 500_000,
        configuration: picosecond_configuration
      )

    assert {:ok, ~U[1958-01-01 00:00:00.000001Z], evidence} =
             Correlation.cds_to_datetime(picosecond, rounding: :nearest)

    assert evidence.error == {1, 2}

    leap_configuration = CDSConfiguration.new!(day_length: :positive_leap)

    leap =
      CDS.new!(
        day_count: 1,
        milliseconds_of_day: 86_400_000,
        submilliseconds: 0,
        configuration: leap_configuration
      )

    assert {:error, :cds_leap_second_not_representable_as_datetime} =
             Correlation.cds_to_datetime(leap)

    edge =
      CDS.new!(
        day_count: 1,
        milliseconds_of_day: 86_399_999,
        submilliseconds: 999_999_999,
        configuration: %{leap_configuration | submillisecond_octets: 4}
      )

    assert {:error, :cds_rounding_enters_unrepresentable_leap_second} =
             Correlation.cds_to_datetime(edge, rounding: :nearest)
  end

  test "requires agency epochs and reports millisecond quantization" do
    configuration = CDSConfiguration.new!(epoch: :agency, day_length: :normal)

    assert {:error, :agency_epoch_date_required} =
             Correlation.datetime_to_cds(~U[2026-01-01 00:00:00Z], configuration)

    datetime = ~U[2026-01-01 00:00:00.000600Z]

    assert {:ok, value, evidence} =
             Correlation.datetime_to_cds(
               datetime,
               configuration,
               epoch_date: ~D[2026-01-01],
               rounding: :nearest
             )

    assert value.day_count == 0
    assert value.milliseconds_of_day == 1
    assert evidence.error == {400, 1}
  end

  test "carries rounded millisecond time into the next CDS day" do
    configuration = CDSConfiguration.new!(day_length: :normal)
    datetime = ~U[1958-01-01 23:59:59.999600Z]

    assert {:ok, value, _evidence} =
             Correlation.datetime_to_cds(datetime, configuration, rounding: :nearest)

    assert value.day_count == 1
    assert value.milliseconds_of_day == 0
  end
end
