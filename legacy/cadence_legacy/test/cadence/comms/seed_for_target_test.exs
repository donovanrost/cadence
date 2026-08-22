defmodule Cadence.Comms.SeedForTargetTest do
  use Cadence.DataCase, async: true

  alias Cadence.Comms
  alias Cadence.Links.{Channel, ChannelActiveSelection, ChannelTarget, Link, ProtocolConfig}
  alias Cadence.Missions.Mission
  alias Cadence.Repo

  import Cadence.TargetsFixtures

  test "seeds comms defaults for a spacecraft target idempotently" do
    target = target_fixture()

    mission = Repo.get!(Mission, target.mission_id)
    org_id = mission.organization_id

    assert mission.config_generation == 1

    assert {:ok, result} =
             Comms.seed_for_target(org_id, mission.id, target.id, target.scid,
               channel_direction: :both
             )

    link = Repo.get_by!(Link, mission_id: mission.id, scid: target.scid)
    assert result.link.id == link.id

    assert Repo.get_by!(ProtocolConfig, link_id: link.id)

    channel =
      Channel
      |> where([c], c.link_id == ^link.id and c.vcid == 0 and is_nil(c.map_id))
      |> Repo.one!()

    assert result.channel.id == channel.id
    assert channel.scid == target.scid
    assert channel.direction == :both

    assert ChannelTarget
           |> where(
             [ct],
             ct.mission_id == ^mission.id and ct.target_id == ^target.id and
               ct.scid == ^target.scid and ct.vcid == 0 and is_nil(ct.map_id) and
               ct.purpose == "primary_uplink"
           )
           |> Repo.one!()

    assert ChannelTarget
           |> where(
             [ct],
             ct.mission_id == ^mission.id and ct.target_id == ^target.id and
               ct.scid == ^target.scid and ct.vcid == 0 and is_nil(ct.map_id) and
               ct.purpose == "primary_downlink"
           )
           |> Repo.one!()

    selection = Repo.get_by!(ChannelActiveSelection, channel_id: channel.id, direction: :uplink)
    assert selection.binding_id == nil

    mission = Repo.get!(Mission, mission.id)
    assert mission.config_generation == 2

    assert {:ok, _result} = Comms.seed_for_target(org_id, mission.id, target.id, target.scid)

    mission = Repo.get!(Mission, mission.id)
    assert mission.config_generation == 2
  end
end
