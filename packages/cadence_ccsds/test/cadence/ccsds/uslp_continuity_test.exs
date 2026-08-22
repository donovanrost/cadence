defmodule Cadence.CCSDS.USLPContinuityTest do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.Core.LinkFrame
  alias Cadence.CCSDS.SDLP.USLP.Continuity

  test "tracks Sequence-Controlled and Expedited counters independently" do
    state = Continuity.init()

    assert {:ok, %{status: :first}, state} =
             Continuity.observe(frame(:sequence_controlled, 254, 1), state)

    assert {:ok, %{status: :first}, state} = Continuity.observe(frame(:expedited, 9, 2), state)

    assert {:ok, %{status: :continuous, expected: 255}, state} =
             Continuity.observe(frame(:sequence_controlled, 255, 1), state)

    assert {:ok, %{status: :continuous, expected: 0}, _state} =
             Continuity.observe(frame(:sequence_controlled, 0, 1), state)
  end

  test "reports loss and leaves uncounted truncated frames untracked" do
    assert {:ok, %{status: :first}, state} =
             Continuity.observe(frame(:expedited, 10, 2), Continuity.init())

    assert {:ok, %{status: :discontinuity, loss?: true, expected: 11}, state} =
             Continuity.observe(frame(:expedited, 15, 2), state)

    assert {:ok, %{status: :untracked, loss?: false}, ^state} =
             Continuity.observe(frame(:expedited, nil, 0), state)
  end

  defp frame(qos, count, count_octets) do
    %LinkFrame{
      profile: :uslp,
      scid: 123,
      vcid: 5,
      map_id: 2,
      frame_seq: count,
      payload_octets: <<1>>,
      quality: :good,
      meta: %{qos: qos, vcf_count: count, vcf_count_length: count_octets}
    }
  end
end
