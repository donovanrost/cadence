defmodule CadenceSimulator.IngressBenchmark.DeterministicPatternTest do
  use ExUnit.Case, async: true

  alias CadenceSimulator.IngressBenchmark.DeterministicPattern
  alias CCSDS.SDLP.TM.FrameCodec

  test "TM corpus emits fixed frames with continuous counters across arbitrary slices" do
    frame_size = 62_500

    assert {:ok, pattern} =
             DeterministicPattern.new(381_746, frame_size, "ccsds-tm-frame-v1")

    stream = DeterministicPattern.slice(pattern, frame_size - 11, frame_size + 22)

    assert stream ==
             DeterministicPattern.slice(pattern, frame_size - 11, 11) <>
               DeterministicPattern.slice(pattern, frame_size, frame_size) <>
               DeterministicPattern.slice(pattern, frame_size * 2, 11)

    frames = DeterministicPattern.slice(pattern, 0, frame_size * 3)
    first_frame = binary_part(frames, 0, frame_size)
    second_frame = binary_part(frames, frame_size, frame_size)

    assert binary_part(first_frame, 12, frame_size - 12) ==
             binary_part(second_frame, 12, frame_size - 12)

    assert {:ok, decoded, <<>>} =
             FrameCodec.decode(frames, frame_size: frame_size, ocf_length: 0)

    assert Enum.map(decoded, & &1.frame_seq) == [0, 1, 2]
    assert Enum.map(decoded, &Map.fetch!(&1.meta, :mcfc)) == [0, 1, 2]
    assert Enum.all?(decoded, &(byte_size(&1.payload_octets) == frame_size - 6))
  end

  test "TM corpus rejects a frame whose packet length cannot be represented" do
    assert {:error, message} =
             DeterministicPattern.new(381_746, 65_549, "ccsds-tm-frame-v1")

    assert message =~ "13..65548"
  end
end
