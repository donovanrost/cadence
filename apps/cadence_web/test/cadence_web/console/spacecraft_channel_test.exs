defmodule CadenceWeb.Console.SpacecraftChannelTest do
  @moduledoc "M8: spacecraft:<mission_id>:<spacecraft_id> live point values."
  use CadenceWeb.ConnCase, async: false

  import Phoenix.ChannelTest, except: [connect: 2, connect: 3]
  require Phoenix.ChannelTest

  alias Cadence.Dashboards.RuntimeInvalidation
  alias CadenceWeb.{ConsoleSocket, ControlPlaneApiFixtures}
  alias CadenceWeb.TestFixtures

  @endpoint CadenceWeb.Endpoint

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)
    craft = TestFixtures.persist_spacecraft!(mission, display_name: "EARENDIL-001")
    token = TestFixtures.member_session_token!(user)

    {:ok, socket} =
      Phoenix.ChannelTest.connect(ConsoleSocket, %{},
        connect_info: %{session: %{"user_session_token" => token}}
      )

    %{org: org, mission: mission, craft: craft, socket: socket}
  end

  defp topic(c, spacecraft_id \\ nil),
    do: "spacecraft:#{c.mission.mission_id}:#{spacecraft_id || c.craft.spacecraft_id}"

  defp invalidate(c),
    do:
      RuntimeInvalidation.source_watermark_changed(%{
        organization_id: c.org.organization_id,
        mission_id: c.mission.mission_id
      })

  test "an empty join selects nothing and pushes an empty first snapshot", c do
    assert {:ok, %{points: [], spacecraft_id: id}, _socket} =
             subscribe_and_join(c.socket, topic(c), %{})

    assert id == c.craft.spacecraft_id
    assert_push("points", %{seq: 1, samples: []}, 2_000)
  end

  test "selected points: the first push has current values, then only changes", c do
    # Ingests one HK packet for spacecraft-001 (HK.counter = 30, a caution limit).
    ControlPlaneApiFixtures.seed_mission_read_models(c.org.organization_id, c.mission.mission_id)
    topic = "spacecraft:#{c.mission.mission_id}:spacecraft-001"

    assert {:ok, %{points: [%{point_id: "HK.counter", type: type}, %{point_id: "HK.nope"}]},
            socket} =
             subscribe_and_join(c.socket, topic, %{"point_ids" => ["HK.counter", "HK.nope"]})

    assert type in ["numeric", nil]

    assert_push("points", %{seq: 1, samples: [sample]}, 2_000)

    assert %{point_id: "HK.counter", value_json: "30", limit_state: "caution", generation_time: _} =
             sample

    # Nothing changed: an invalidation pushes nothing.
    invalidate(c)
    refute_push("points", _payload, 1_500)

    # A new selection replies with its points and pushes their current values.
    ref = Phoenix.ChannelTest.push(socket, "points:set", %{"point_ids" => ["HK.counter"]})

    # The default 100 ms flaked under load (devops 11-17, seed 925505); its neighbours allow 2-3 s.
    assert_reply(ref, :ok, %{points: [%{point_id: "HK.counter"}]}, 2_000)
    assert_push("points", %{seq: 2, samples: [%{point_id: "HK.counter"}]}, 3_000)
  end

  test "join errors: another spacecraft, another organization's mission, too many points", c do
    assert {:error, %{reason: "spacecraft_not_found"}} =
             subscribe_and_join(c.socket, topic(c, "nobody"), %{})

    other_mission = TestFixtures.persist_mission!(TestFixtures.persist_org!())

    assert {:error, %{reason: "mission_not_found"}} =
             subscribe_and_join(c.socket, "spacecraft:#{other_mission.mission_id}:x", %{})

    ids = for n <- 1..201, do: "P#{n}"

    assert {:error, %{reason: "too_many_points"}} =
             subscribe_and_join(c.socket, topic(c), %{"point_ids" => ids})
  end
end
