defmodule CCSDS.SDLP.TM.ContinuityTest do
  use ExUnit.Case, async: true

  alias CCSDS.Core.LinkFrame
  alias CCSDS.SDLP.TM.Continuity

  test "tracks MCFC and VCFC independently across multiplexed Virtual Channels" do
    state = Continuity.init()

    assert {:ok, first, state} = Continuity.observe(frame(9, 1, 254, 10), state)
    assert first.master_channel.status == :first
    assert first.virtual_channel.status == :first

    assert {:ok, second, state} = Continuity.observe(frame(9, 2, 255, 80), state)
    assert second.master_channel.status == :continuous
    assert second.virtual_channel.status == :first

    assert {:ok, wrapped, state} = Continuity.observe(frame(9, 1, 0, 11), state)
    assert wrapped.master_channel.status == :continuous
    assert wrapped.virtual_channel.status == :continuous
    assert wrapped.anomalies == []

    assert {:ok, gap, _state} = Continuity.observe(frame(9, 1, 1, 14), state)
    assert gap.master_channel.status == :continuous
    assert gap.virtual_channel.status == :discontinuity
    assert gap.virtual_channel.forward_distance == 2
    assert [%{anomaly_kind: :virtual_channel_frame_count_discontinuity}] = gap.anomalies
  end

  test "keeps identical VCIDs on different spacecraft independent" do
    state = Continuity.init()
    assert {:ok, _, state} = Continuity.observe(frame(1, 2, 5, 6), state)
    assert {:ok, report, _state} = Continuity.observe(frame(2, 2, 90, 120), state)
    assert report.master_channel.status == :first
    assert report.virtual_channel.status == :first
  end

  defp frame(scid, vcid, mcfc, vcfc) do
    %LinkFrame{
      profile: :tm,
      scid: scid,
      vcid: vcid,
      frame_seq: vcfc,
      payload_octets: <<0>>,
      quality: :good,
      meta: %{mcfc: mcfc, vcfc: vcfc, fhp: 0}
    }
  end
end
