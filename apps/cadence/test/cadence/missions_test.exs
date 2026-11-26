defmodule Cadence.MissionsTest do
  use Cadence.DataCase, async: false

  import Ecto.Query

  alias Cadence.Missions
  alias Cadence.Repo

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
          # This test's own queries, and those of processes it starts (`$callers`).
          ours? = self() == test_pid or test_pid in Process.get(:"$callers", [])

          if metadata.source == "missions" and ours?,
            do: send(test_pid, {:missions_query, self()})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert Missions.organization_id_for_mission("mission-created-later") == nil
    assert_received {:missions_query, ^test_pid}

    persist_mission_scope("org-missions-memo", "mission-created-later")
    flush_queries()

    # The miss was not memoized: the new mission is found, with one query.
    assert Missions.organization_id_for_mission("mission-created-later") == "org-missions-memo"
    assert_received {:missions_query, ^test_pid}

    # Found once: later calls in this process ask nothing.
    assert Missions.organization_id_for_mission("mission-created-later") == "org-missions-memo"
    assert Missions.organization_id_for_mission("mission-created-later") == "org-missions-memo"
    refute_received {:missions_query, _pid}

    # Another process has its own memo and asks once itself.
    task = Task.async(fn -> Missions.organization_id_for_mission("mission-created-later") end)
    assert Task.await(task) == "org-missions-memo"
    task_pid = task.pid
    assert_received {:missions_query, ^task_pid}
  end

  test "the database refuses to change a mission's organization or id (#687, #774)" do
    persist_mission_scope("org-missions-fixed", "mission-missions-fixed")

    for change <- [
          [organization_id: "org-missions-other"],
          [mission_id: "mission-missions-renamed"]
        ] do
      assert_raise Postgrex.Error, ~r/never change/, fn ->
        Repo.transaction(fn ->
          from(m in "missions", where: m.mission_id == "mission-missions-fixed")
          |> Repo.update_all(set: change)
        end)
      end
    end

    assert Missions.organization_id_for_mission("mission-missions-fixed") == "org-missions-fixed"
  end

  defp flush_queries do
    receive do
      {:missions_query, _pid} -> flush_queries()
    after
      0 -> :ok
    end
  end
end
