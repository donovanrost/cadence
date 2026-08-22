defmodule Cadence.CCSDS.SDLP.AOS.ContinuityTest do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.Core.LinkFrame
  alias Cadence.CCSDS.SDLP.AOS.Continuity

  test "tracks the 28-bit count through VCFC wrap" do
    state = Continuity.init()

    assert {:ok, %{status: :first}, state} =
             Continuity.observe(frame(0xFFFFFF, cycle: 2), state)

    assert {:ok, report, _state} = Continuity.observe(frame(0, cycle: 3), state)
    assert report.status == :continuous
    assert report.observed == 0x3000000
    refute report.loss?
  end

  test "separates replay continuity and does not track OID VCFC" do
    state = Continuity.init()
    assert {:ok, %{status: :first, replay?: false}, state} = Continuity.observe(frame(10), state)

    assert {:ok, %{status: :first, replay?: true}, state} =
             Continuity.observe(frame(90, replay: 1), state)

    oid = frame(99) |> Map.put(:vcid, 63)
    assert {:ok, %{status: :untracked}, ^state} = Continuity.observe(oid, state)
  end

  defp frame(vcfc, opts \\ []) do
    cycle = Keyword.get(opts, :cycle, 0)
    cycle_use = if(cycle > 0 or Keyword.get(opts, :cycle_use, false), do: 1, else: 0)

    %LinkFrame{
      profile: :aos,
      scid: 513,
      vcid: 4,
      frame_seq: vcfc,
      payload_octets: <<0>>,
      quality: :good,
      meta: %{
        vcfc: vcfc,
        replay_flag: Keyword.get(opts, :replay, 0),
        vc_frame_count_cycle_use_flag: cycle_use,
        vc_frame_count_cycle: cycle
      }
    }
  end
end
