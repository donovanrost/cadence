defmodule Cadence.MissionsTest do
  use Cadence.DataCase, async: false

  alias Cadence.Missions

  test "resolves organization ownership for a persisted mission" do
    persist_mission_scope("org-missions-owner", "mission-missions-owner")

    assert Missions.organization_id_for_mission("mission-missions-owner") ==
             "org-missions-owner"

    assert Missions.organization_id_for_mission("mission-missing") == nil
  end

  test "a found organization costs one query per process; a miss is asked again (#687)" do
    test_pid = self()
    handler_id = "missions-org-lookup-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler_id,
        [:cadence, :repo, :query],
        fn _event, _measurements, metadata, _config ->
          if metadata.source == "missions" and self() == test_pid,
            do: send(test_pid, :missions_query)
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert Missions.organization_id_for_mission("mission-created-later") == nil
    assert_received :missions_query

    persist_mission_scope("org-missions-memo", "mission-created-later")
    flush_queries()

    # The miss was not memoized: the new mission is found, with one query.
    assert Missions.organization_id_for_mission("mission-created-later") == "org-missions-memo"
    assert_received :missions_query

    # Found once: later calls in this process ask nothing.
    assert Missions.organization_id_for_mission("mission-created-later") == "org-missions-memo"
    assert Missions.organization_id_for_mission("mission-created-later") == "org-missions-memo"
    refute_received :missions_query

    # Another process has its own memo and asks once itself.
    assert Task.async(fn -> Missions.organization_id_for_mission("mission-created-later") end)
           |> Task.await() == "org-missions-memo"
  end

  defp flush_queries do
    receive do
      :missions_query -> flush_queries()
    after
      0 -> :ok
    end
  end
end
