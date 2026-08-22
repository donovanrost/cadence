defmodule CCSDS.CDSTimeTest do
  use ExUnit.Case, async: true

  alias CCSDS.Time.CDS
  alias CCSDS.Time.CDS.{Codec, Configuration, Preamble}

  test "encodes and decodes the Level 1 millisecond form" do
    configuration = Configuration.new!()

    value =
      CDS.new!(
        day_count: 0x1234,
        milliseconds_of_day: 0x01020304,
        submilliseconds: 0,
        configuration: configuration
      )

    expected = hex("40123401020304")
    assert {:ok, ^expected} = Codec.encode(value)
    assert {:ok, ^value} = Codec.decode(expected)
  end

  test "encodes the agency epoch, 24-bit day, and microsecond form" do
    configuration =
      Configuration.new!(epoch: :agency, day_octets: 3, submillisecond_octets: 2)

    value =
      CDS.new!(
        day_count: 0x010203,
        milliseconds_of_day: 0x04050607,
        submilliseconds: 999,
        configuration: configuration
      )

    expected = hex("4D0102030405060703E7")
    assert {:ok, ^expected} = Codec.encode(value)
    assert {:ok, ^value} = Codec.decode(expected)
  end

  test "encodes the 32-bit picosecond form" do
    configuration = Configuration.new!(day_octets: 3, submillisecond_octets: 4)

    value =
      CDS.new!(
        day_count: 0x010203,
        milliseconds_of_day: 0x04050607,
        submilliseconds: 999_999_999,
        configuration: configuration
      )

    expected = hex("46010203040506073B9AC9FF")
    assert {:ok, ^expected} = Codec.encode(value)
    assert {:ok, ^value} = Codec.decode(expected)
    assert CDS.submillisecond_fraction(value) == {999_999_999, 1_000_000_000}
  end

  test "supports implicit P-fields and incomplete streaming boundaries" do
    configuration = Configuration.new!(submillisecond_octets: 2)

    value =
      CDS.new!(
        day_count: 1,
        milliseconds_of_day: 2,
        submilliseconds: 3,
        configuration: configuration
      )

    assert {:ok, implicit} = Codec.encode(value, preamble: false)
    assert byte_size(implicit) == 8

    assert {:ok, ^value, <<0xAA>>} =
             Codec.decode_prefix(
               implicit <> <<0xAA>>,
               preamble: false,
               configuration: configuration
             )

    {:ok, explicit} = Codec.encode(value)

    for split <- 0..(byte_size(explicit) - 1) do
      <<prefix::binary-size(^split), _rest::binary>> = explicit
      assert {:incomplete, ^prefix} = Codec.decode_prefix(prefix)
    end
  end

  test "enforces counter ranges for normal and leap-adjusted days" do
    normal = Configuration.new!(day_length: :normal)
    positive = Configuration.new!(day_length: :positive_leap)
    negative = Configuration.new!(day_length: :negative_leap)

    attrs = [day_count: 1, milliseconds_of_day: 86_400_500, configuration: positive]
    assert {:ok, _value} = CDS.new(attrs)

    assert {:error, {:invalid_cds_milliseconds_of_day, 86_400_500, 86_399_999}} =
             CDS.new(Keyword.put(attrs, :configuration, normal))

    assert {:error, {:invalid_cds_milliseconds_of_day, 86_399_000, 86_398_999}} =
             CDS.new(
               attrs
               |> Keyword.put(:milliseconds_of_day, 86_399_000)
               |> Keyword.put(:configuration, negative)
             )

    assert {:error, {:invalid_cds_submilliseconds, 1_000, 2}} =
             CDS.new(
               day_count: 1,
               milliseconds_of_day: 1,
               submilliseconds: 1_000,
               configuration: Configuration.new!(submillisecond_octets: 2)
             )
  end

  test "rejects reserved P-field values and unsupported extensions" do
    assert {:error, :reserved_cds_submillisecond_length} =
             Preamble.decode_prefix(<<0x43>>)

    assert {:error, :unsupported_cds_preamble_extension} =
             Preamble.decode_prefix(<<0xC0>>)

    assert {:error, {:invalid_cds_time_code_identification, 5}} =
             Preamble.decode_prefix(<<0x50>>)
  end

  defp hex(value), do: Base.decode16!(value)
end
