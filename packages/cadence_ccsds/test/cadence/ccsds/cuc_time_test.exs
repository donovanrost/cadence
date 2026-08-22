defmodule Cadence.CCSDS.CUCTimeTest do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.Time.CUC
  alias Cadence.CCSDS.Time.CUC.{Codec, Configuration, Preamble}

  test "encodes and decodes the one-octet Level 1 P-field and T-field" do
    configuration = Configuration.new!(coarse_octets: 4, fine_octets: 3)

    value =
      CUC.new!(
        coarse_time: 0x01020304,
        fine_time: 0xAABBCC,
        configuration: configuration
      )

    expected = hex("1F01020304AABBCC")
    assert {:ok, ^expected} = Codec.encode(value)
    assert {:ok, ^value} = Codec.decode(expected)

    assert {:ok, ^configuration, time_field, <<0x1F>>} =
             Preamble.decode_prefix(expected)

    assert time_field == hex("01020304AABBCC")
  end

  test "encodes and decodes the extended agency P-field at maximum lengths" do
    configuration =
      Configuration.new!(
        epoch: :agency,
        coarse_octets: 7,
        fine_octets: 10,
        basic_unit: {1, 1_000},
        mission_bits: 2
      )

    value =
      CUC.new!(
        coarse_time: 0x01020304050607,
        fine_time: 0x0102030405060708090A,
        configuration: configuration
      )

    expected = hex("AF7E010203040506070102030405060708090A")
    assert {:ok, ^expected} = Codec.encode(value)

    assert {:ok, decoded} = Codec.decode(expected, basic_unit: {1, 1_000})
    assert decoded == value
  end

  test "supports implicit managed P-fields and preserves trailing data" do
    configuration = Configuration.new!(epoch: :agency, coarse_octets: 2, fine_octets: 1)
    value = CUC.new!(coarse_time: 0x1234, fine_time: 0x56, configuration: configuration)

    assert {:ok, encoded} = Codec.encode(value, preamble: false)
    assert encoded == hex("123456")

    assert {:ok, ^value, <<0xAA>>} =
             Codec.decode_prefix(
               encoded <> <<0xAA>>,
               preamble: false,
               configuration: configuration
             )

    assert {:error, :cuc_configuration_required} =
             Codec.decode_prefix(encoded, preamble: false)
  end

  test "returns the original buffer at every incomplete explicit boundary" do
    configuration = Configuration.new!(coarse_octets: 4, fine_octets: 3)
    value = CUC.new!(coarse_time: 1, fine_time: 2, configuration: configuration)
    {:ok, encoded} = Codec.encode(value)

    for split <- 0..(byte_size(encoded) - 1) do
      <<prefix::binary-size(^split), _rest::binary>> = encoded
      assert {:incomplete, ^prefix} = Codec.decode_prefix(prefix)
    end

    assert {:ok, ^value, <<>>} = Codec.decode_prefix(encoded)
  end

  test "rejects reserved identifiers, unsupported extensions, and counter overflow" do
    assert {:error, {:invalid_cuc_time_code_identification, 0}} =
             Preamble.decode_prefix(<<0>>)

    assert {:error, :unsupported_cuc_preamble_extension} =
             Preamble.decode_prefix(<<0x90, 0x80>>)

    configuration = Configuration.new!(coarse_octets: 1, fine_octets: 0)

    assert {:error, {:invalid_cuc_counter, :coarse_time, 256, 1}} =
             CUC.new(coarse_time: 256, fine_time: 0, configuration: configuration)

    assert {:error, {:invalid_cuc_counter, :fine_time, 1, 0}} =
             CUC.new(coarse_time: 1, fine_time: 1, configuration: configuration)
  end

  test "uses exact fractions and reports bounded quantization" do
    configuration = Configuration.new!(coarse_octets: 2, fine_octets: 1)

    assert {:ok, value, evidence} =
             CUC.from_elapsed_fraction({1, 3}, configuration, :nearest)

    assert value.coarse_time == 0
    assert value.fine_time == 85
    assert CUC.elapsed_fraction(value) == {85, 256}
    assert evidence.error_seconds == {-1, 768}

    equivalent =
      CUC.new!(
        coarse_time: 0,
        fine_time: 21_760,
        configuration: Configuration.new!(coarse_octets: 1, fine_octets: 2)
      )

    assert CUC.compare(value, equivalent) == :eq
  end

  defp hex(value), do: Base.decode16!(value)
end
