defmodule CCSDS.ChannelCoding.CLTUTest do
  use ExUnit.Case, async: true

  alias CCSDS.ChannelCoding.{CLTU, Configuration}

  test "validates code-specific managed parameters" do
    assert {:ok, %Configuration{code: :bch, randomize?: false}} = Configuration.new()

    assert {:ok, %Configuration{code: :ldpc_128_64, randomize?: true, ldpc_tail?: true}} =
             Configuration.new(code: :ldpc_128_64)

    assert {:ok, %Configuration{code: :ldpc_512_256, randomize?: true, ldpc_tail?: false}} =
             Configuration.new(code: :ldpc_512_256)

    assert {:error, {:randomization_required, :ldpc_128_64}} =
             Configuration.new(code: :ldpc_128_64, randomize?: false)

    assert {:error, {:tail_sequence_forbidden, :ldpc_512_256}} =
             Configuration.new(code: :ldpc_512_256, ldpc_tail?: true)
  end

  test "encodes the normative BCH envelope and recovers multiple transfer frames plus fill" do
    configuration = Configuration.new!()
    frames = [<<1, 2, 3>>, <<4, 5>>]

    assert {:ok, cltu, metadata} = CLTU.encode(frames, configuration)
    assert <<0xEB, 0x90, _encoded::binary-size(8), tail::binary-size(8)>> = cltu
    assert tail == <<0xC5, 0xC5, 0xC5, 0xC5, 0xC5, 0xC5, 0xC5, 0x79>>
    assert metadata.codeword_count == 1
    assert metadata.fill_octets == 2

    assert {:ok, decoded} =
             CLTU.decode(cltu, configuration, expected_data_octets: 5)

    assert decoded.data == <<1, 2, 3, 4, 5>>
    assert decoded.trailing_fill == <<0x55, 0x55>>
    assert decoded.quality.status == :clean
    assert decoded.quality.fill_valid?
  end

  test "supports optional BCH randomization and ambiguity resolution" do
    configuration = Configuration.new!(randomize?: true)
    data = <<1, 2, 3, 4, 5, 6, 7, 8>>

    assert {:ok, cltu, _metadata} = CLTU.encode(data, configuration)
    inverted = invert(cltu)

    assert {:ok, decoded} =
             CLTU.decode(inverted, configuration, expected_data_octets: byte_size(data))

    assert decoded.data == data
    assert decoded.quality.inverted?
  end

  test "allows one BCH start error only when managed and corrects one codeword error" do
    configuration =
      Configuration.new!(
        bch_decoding_mode: :correct,
        allowed_start_errors: 1
      )

    assert {:ok, cltu, _metadata} = CLTU.encode(<<1, 2, 3, 4, 5, 6, 7>>, configuration)
    corrupted = cltu |> flip_bit(3) |> flip_bit(16 + 9)

    assert {:ok, decoded} =
             CLTU.decode(corrupted, configuration, expected_data_octets: 7)

    assert decoded.data == <<1, 2, 3, 4, 5, 6, 7>>
    assert decoded.quality.start_errors == 1
    assert decoded.quality.status == :corrected
    assert decoded.quality.corrected_codewords == 1
  end

  test "uses the Corrigendum 1 LDPC(128,64) tail and resets randomization per codeword" do
    configuration = Configuration.new!(code: :ldpc_128_64)
    data = :binary.copy(<<0>>, 16)

    assert {:ok, cltu, metadata} = CLTU.encode(data, configuration)

    assert <<
             0x03,
             0x47,
             0x76,
             0xC7,
             0x27,
             0x28,
             0x95,
             0xB0,
             first_codeword::binary-size(16),
             second_codeword::binary-size(16),
             tail::binary-size(16)
           >> = cltu

    assert first_codeword == second_codeword

    assert tail ==
             <<0x63, 0xA1, 0xED, 0x72, 0xC6, 0xAC, 0x79, 0xE2, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55,
               0x55, 0x55>>

    assert metadata.codeword_count == 2
    assert {:ok, %{data: ^data}} = CLTU.decode(cltu, configuration, expected_data_octets: 16)
  end

  test "LDPC(512,256) omits a tail and exposes correction evidence" do
    configuration = Configuration.new!(code: :ldpc_512_256)
    data = :binary.copy(<<0xA5>>, 32)

    assert {:ok, cltu, %{tail?: false, cltu_octets: 72}} = CLTU.encode(data, configuration)
    corrupted = flip_bit(cltu, 64 + 300)

    assert {:ok, decoded} =
             CLTU.decode(corrupted, configuration, expected_data_octets: 32)

    assert decoded.data == data
    assert decoded.quality.status == :corrected
    assert decoded.quality.corrected_codewords == 1
  end

  test "rejects malformed envelopes, invalid fill, and maximum-length violations" do
    configuration = Configuration.new!()
    assert {:ok, cltu, _metadata} = CLTU.encode(<<1, 2, 3>>, configuration)

    assert {:error, {:start_sequence_not_found, _normal, _inverted}} =
             CLTU.decode(<<0, 0>> <> binary_part(cltu, 2, byte_size(cltu) - 2), configuration)

    assert {:error, {:invalid_tail_sequence, _tail}} =
             cltu |> flip_bit(bit_size(cltu) - 1) |> CLTU.decode(configuration)

    limited = Configuration.new!(max_cltu_octets: byte_size(cltu) - 1)

    assert {:error, {:maximum_cltu_length_exceeded, _, _}} =
             CLTU.encode(<<1, 2, 3>>, limited)
  end

  defp invert(binary) do
    binary
    |> :binary.bin_to_list()
    |> Enum.map(&Bitwise.bxor(&1, 0xFF))
    |> :binary.list_to_bin()
  end

  defp flip_bit(binary, wire_bit) do
    <<prefix::bitstring-size(^wire_bit), bit::1, suffix::bitstring>> = binary
    <<prefix::bitstring, Bitwise.bxor(bit, 1)::1, suffix::bitstring>>
  end
end
