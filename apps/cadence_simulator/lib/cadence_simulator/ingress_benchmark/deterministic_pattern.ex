defmodule CadenceSimulator.IngressBenchmark.DeterministicPattern do
  @moduledoc """
  Bounded, repeatable byte pattern with random-access slicing.

  The pattern is generated once from SHA-256 blocks and repeated. It avoids a
  corpus file for laptop source-capacity smoke runs while preserving exact byte
  identity at arbitrary TCP read boundaries.
  """

  @default_size 65_536
  @maximum_size 4_194_304

  @enforce_keys [:seed, :bytes, :size, :sha256]
  defstruct [:seed, :bytes, :size, :sha256, kind: :sha256_blocks]

  @type t :: %__MODULE__{
          seed: non_neg_integer(),
          bytes: binary(),
          size: pos_integer(),
          sha256: binary(),
          kind: :sha256_blocks | :ccsds_tm_frame
        }

  @spec new(non_neg_integer(), pos_integer()) :: {:ok, t()} | {:error, binary()}
  def new(seed, size \\ @default_size)

  def new(seed, size)
      when is_integer(seed) and seed >= 0 and is_integer(size) and size > 0 and
             size <= @maximum_size do
    bytes = build(seed, size)

    {:ok,
     %__MODULE__{
       seed: seed,
       bytes: bytes,
       size: size,
       sha256: digest(bytes)
     }}
  end

  def new(_seed, _size) do
    {:error, "traffic seed must be non-negative and pattern_size_bytes must be 1..4194304"}
  end

  @spec new(non_neg_integer(), pos_integer(), binary()) :: {:ok, t()} | {:error, binary()}
  def new(seed, size, "deterministic-pattern-v1"), do: new(seed, size)

  def new(seed, size, "ccsds-tm-frame-v1")
      when is_integer(seed) and seed >= 0 and is_integer(size) and size in 13..65_548 do
    bytes = build_tm_frame(seed, size, 0)

    {:ok,
     %__MODULE__{
       seed: seed,
       bytes: bytes,
       size: size,
       sha256: digest(bytes),
       kind: :ccsds_tm_frame
     }}
  end

  def new(_seed, _size, "ccsds-tm-frame-v1") do
    {:error, "ccsds-tm-frame-v1 pattern_size_bytes must be 13..65548"}
  end

  def new(_seed, _size, corpus_id) when is_binary(corpus_id) do
    {:error, "unsupported traffic.corpus_id: #{corpus_id}"}
  end

  @spec slice(t(), non_neg_integer(), non_neg_integer()) :: binary()
  def slice(%__MODULE__{}, _offset, 0), do: <<>>

  def slice(%__MODULE__{kind: :ccsds_tm_frame} = pattern, offset, length)
      when is_integer(offset) and offset >= 0 and is_integer(length) and length > 0 do
    first_frame = div(offset, pattern.size)
    first_frame_offset = rem(offset, pattern.size)
    required_bytes = first_frame_offset + length
    frame_count = div(required_bytes + pattern.size - 1, pattern.size)
    packet_data = binary_part(pattern.bytes, 12, pattern.size - 12)

    stream =
      for frame_offset <- 0..(frame_count - 1), into: <<>> do
        encode_tm_frame(pattern.size, first_frame + frame_offset, packet_data)
      end

    binary_part(stream, first_frame_offset, length)
  end

  def slice(%__MODULE__{} = pattern, offset, length)
      when is_integer(offset) and offset >= 0 and is_integer(length) and length > 0 do
    start = rem(offset, pattern.size)
    prefix_size = min(length, pattern.size - start)
    prefix = binary_part(pattern.bytes, start, prefix_size)
    remaining = length - prefix_size
    copies = div(remaining, pattern.size)
    tail_size = rem(remaining, pattern.size)

    IO.iodata_to_binary([
      prefix,
      :binary.copy(pattern.bytes, copies),
      binary_part(pattern.bytes, 0, tail_size)
    ])
  end

  @spec digest(binary()) :: binary()
  def digest(bytes) when is_binary(bytes) do
    :crypto.hash(:sha256, bytes)
    |> Base.encode16(case: :lower)
  end

  defp build(seed, size) do
    block_count = div(size + 31, 32)

    bytes =
      for counter <- 0..(block_count - 1), into: <<>> do
        :crypto.hash(:sha256, <<seed::unsigned-64, counter::unsigned-64>>)
      end

    binary_part(bytes, 0, size)
  end

  defp build_tm_frame(seed, frame_size, frame_number) do
    packet_data_size = frame_size - 12
    packet_data = build(seed, packet_data_size)
    encode_tm_frame(frame_size, frame_number, packet_data)
  end

  defp encode_tm_frame(frame_size, frame_number, packet_data) do
    packet_length = frame_size - 13
    counter = rem(frame_number, 256)
    packet_sequence = rem(frame_number, 16_384)

    <<
      0::2,
      11::10,
      2::3,
      0::1,
      counter::8,
      counter::8,
      0::1,
      0::1,
      0::1,
      3::2,
      0::11,
      0::3,
      0::1,
      0::1,
      42::11,
      3::2,
      packet_sequence::14,
      packet_length::16,
      packet_data::binary
    >>
  end
end
