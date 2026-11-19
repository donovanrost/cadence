defmodule CadenceWeb.Console.DashboardChannelTest do
  @moduledoc "C1: dashboard:<mission>:<dashboard> live pushes (docs/apogee/plans/dashboards-live.md)."
  use CadenceWeb.ConnCase, async: false

  import Phoenix.ChannelTest, except: [connect: 2, connect: 3, push: 3]
  import CadenceWeb.OpsDashboardPageTestSupport
  require Phoenix.ChannelTest

  alias Cadence.Dashboards.Documents
  alias CadenceWeb.ConsoleSocket
  alias CadenceWeb.TestFixtures

  setup do
    c = dashboard_page_setup()
    token = TestFixtures.member_session_token!(c.user)

    {:ok, socket} =
      Phoenix.ChannelTest.connect(ConsoleSocket, %{},
        connect_info: %{session: %{"user_session_token" => token}}
      )

    Map.put(c, :socket, socket)
  end

  defp topic(c, id \\ nil),
    do: "dashboard:#{c.mission.mission_id}:#{id || c.document.dashboard_id}"

  defp join!(c) do
    {:ok, reply, socket} = subscribe_and_join(c.socket, topic(c), %{})
    {reply, socket}
  end

  test "join replies with the version; subscribe pushes a full view; set replaces it", c do
    {reply, socket} = join!(c)
    assert reply == %{dashboard_id: c.document.dashboard_id, current_version: 1}

    ref =
      Phoenix.ChannelTest.push(socket, "view:subscribe", %{"runtime" => %{}, "refresh_ms" => nil})

    assert_reply(ref, :ok, %{seq: 0}, 3_000)

    assert_push(
      "view",
      %{seq: 1, full: true, version: 1, snapshot: snapshot, placements: [], removed: []},
      3_000
    )

    assert snapshot.name == c.document.name

    craft = TestFixtures.persist_spacecraft!(c.mission)

    ref =
      Phoenix.ChannelTest.push(socket, "view:set", %{
        "runtime" => %{"from" => "now-6h", "to" => "now", "spacecraft_id" => craft.spacecraft_id},
        "refresh_ms" => 1_000
      })

    assert_reply(ref, :ok, %{seq: 0}, 3_000)
    assert_push("view", %{seq: 1, full: true}, 3_000)

    # Nothing changed in the data, so the 1 s ticks push nothing.
    refute_push("view", %{full: false}, 1_500)
  end

  test "bad subscriptions are refused with the field", c do
    {_reply, socket} = join!(c)

    for {payload, field} <- [
          {%{"runtime" => %{"from" => "now-6h"}, "refresh_ms" => nil}, "range"},
          {%{"runtime" => %{"spacecraft_id" => "someone-elses"}, "refresh_ms" => nil},
           "spacecraft_id"},
          {%{"runtime" => %{}, "refresh_ms" => 10}, "refresh_ms"}
        ] do
      ref = Phoenix.ChannelTest.push(socket, "view:subscribe", payload)
      assert_reply(ref, :error, %{reason: "invalid_params", field: ^field}, 3_000)
    end
  end

  test "a save elsewhere sends version, then a full view; archiving stops it", c do
    {_reply, socket} = join!(c)

    ref =
      Phoenix.ChannelTest.push(socket, "view:subscribe", %{"runtime" => %{}, "refresh_ms" => nil})

    assert_reply(ref, :ok, _, 3_000)
    assert_push("view", %{seq: 1, full: true}, 3_000)

    save(c, %{c.document | name: "Next version"}, 1)

    saver = c.user.user_id

    # The callout names who saved (qa smoke: it said "Saved by Someone").
    assert_push(
      "version",
      %{
        current_version: 2,
        archived: false,
        saved_by: %{kind: "user", id: ^saver, name: name},
        saved_at: %DateTime{}
      },
      3_000
    )

    assert name in [c.user.display_name, c.user.email]

    assert_push(
      "view",
      %{seq: 1, full: true, version: 2, snapshot: %{name: "Next version"}},
      3_000
    )

    :ok =
      Documents.archive(c.org.organization_id, c.mission.mission_id, c.document.dashboard_id, [])

    assert_push("version", %{archived: true}, 3_000)
    refute_push("view", _, 500)
  end

  test "unknown, archived and other organizations' dashboards can't be joined", c do
    assert {:error, %{reason: "dashboard_not_found"}} =
             subscribe_and_join(c.socket, topic(c, "dashboard-nope"), %{})

    :ok =
      Documents.archive(c.org.organization_id, c.mission.mission_id, c.document.dashboard_id, [])

    assert {:error, %{reason: "dashboard_archived"}} = subscribe_and_join(c.socket, topic(c), %{})

    stranger = TestFixtures.persist_org!() |> TestFixtures.persist_mission!()

    assert {:error, %{reason: "mission_not_found"}} =
             subscribe_and_join(c.socket, "dashboard:#{stranger.mission_id}:x", %{})
  end
end
