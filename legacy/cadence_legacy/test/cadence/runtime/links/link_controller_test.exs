defmodule Cadence.Runtime.Links.LinkControllerTest do
  use Cadence.PureCase, async: true

  alias Cadence.Runtime.ChannelId
  alias Cadence.Runtime.Links.LinkController
  alias Cadence.Runtime.Links.ProtocolConfig
  alias Cadence.Runtime.Transport.COP1.Config, as: COP1Config

  setup_mission_registry()

  test "channel overrides apply per ChannelId" do
    mission_id = Cadence.PureCase.random_id()
    scid = 7
    channel_a = ChannelId.new(scid, 0)
    channel_b = ChannelId.new(scid, 1)

    defaults_raw = %{"cop1" => %{"mode" => "fop"}}
    overrides_raw = %{"cop1" => %{"mode" => "bypass"}}

    default_effective = ProtocolConfig.effective_config(defaults_raw, %{})
    override_effective = ProtocolConfig.effective_config(defaults_raw, overrides_raw)

    {:ok, _pid} = start_supervised({LinkController, mission_id: mission_id, scid: scid})

    snapshot = %{
      config_version: 1,
      link_defaults: default_effective,
      effective_protocols: %{
        ChannelId.key(channel_a) => default_effective,
        ChannelId.key(channel_b) => override_effective
      }
    }

    :ok = LinkController.apply_config(mission_id, scid, snapshot)

    Cadence.PureCase.assert_eventually(fn ->
      assert {:ok, config_a} = LinkController.effective_protocol_config(mission_id, channel_a)
      assert {:ok, config_b} = LinkController.effective_protocol_config(mission_id, channel_b)

      assert COP1Config.mode(Map.get(config_a, :cop1, %{})) == :fop
      assert COP1Config.mode(Map.get(config_b, :cop1, %{})) == :bypass
    end)
  end
end
