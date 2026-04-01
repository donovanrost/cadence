defmodule Cadence.Simulator.UplinkRuntimeTest do
  use Cadence.PureCase, async: true

  alias Cadence.Simulator.UplinkRuntime

  test "build returns nil runtime when framing is disabled" do
    assert UplinkRuntime.build(nil, :mission) == %{
             ctx_base: nil,
             encode_opts: nil,
             sdu_base: nil
           }
  end

  test "build precomputes stable uplink encode inputs" do
    runtime =
      UplinkRuntime.build(
        [
          profile: :tm,
          frame_size: 256,
          uplink_scid: 42,
          uplink_vcid: 7,
          uplink_map_id: 3,
          secondary_header_length: 2,
          ocf_length: 4,
          ignored: :value
        ],
        :mission
      )

    assert runtime.ctx_base == %{
             frame_size: 256,
             scid: 42,
             vcid: 7,
             map_id: 3,
             metrics_scope: :mission
           }

    assert Keyword.fetch!(runtime.encode_opts, :frame_size) == 256
    assert Keyword.fetch!(runtime.encode_opts, :secondary_header_length) == 2
    assert Keyword.fetch!(runtime.encode_opts, :ocf_length) == 4
    assert Keyword.fetch!(runtime.encode_opts, :metrics_scope) == :mission

    assert runtime.sdu_base.profile == :tm
    assert runtime.sdu_base.scid == 42
    assert runtime.sdu_base.vcid == 7
    assert runtime.sdu_base.map_id == 3
    assert runtime.sdu_base.direction == :uplink
    assert runtime.sdu_base.sdu_kind_hint == :space_packet
    assert runtime.sdu_base.octets == <<>>
    assert runtime.sdu_base.meta == %{}
  end
end
